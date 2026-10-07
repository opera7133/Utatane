#!/usr/bin/env python3
"""Compile the app's POP3 client and test it with a loopback server.

Run: python3 Scripts/test-pop3-mail.py
Uses synthetic headers and credentials. Never connects to a real mailbox.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
WORK = tempfile.TemporaryDirectory(prefix="utatane-pop3-test-")
PROBE = Path(WORK.name) / "probe"
source = (ROOT / "packages/network/Sources/MailHeaderParser.swift").read_text()
source += "\n" + (ROOT / "apps/Utatane/Sources/POP3MailChecker.swift").read_text().replace("import UtataneNetwork\n", "")
source += r'''
@main struct Probe {
 static func main() async {
  do {
   let result = try await POP3MailChecker.check(configuration: POP3Configuration(accountName: "Test", host: "127.0.0.1", port: UInt16(CommandLine.arguments[1])!, user: "test-user", password: "test-password", usesTLS: false))
   let summaries = result.headerLines.map { MailHeaderParser.parse(lines: $0) }
   let data = try JSONSerialization.data(withJSONObject: ["count": result.messageCount, "headers": summaries.map { ["sender": $0.sender, "subject": $0.subject] }])
   print(String(decoding: data, as: UTF8.self))
  } catch { print("ERROR: \(error)") }
 }
}
'''
swift = Path(WORK.name) / "Probe.swift"
swift.write_text(source)
subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(swift), "-o", str(PROBE)], check=True)
import asyncio,json
async def scenario(mode,count):
    commands=[]
    async def serve(reader,writer):
        writer.write(b"+OK test\r\n"); await writer.drain()
        try:
            while line:=await reader.readline():
                cmd=line.decode().strip(); commands.append(cmd.split()[0])
                if cmd.startswith(("USER ","PASS ")): writer.write(b"+OK\r\n")
                elif cmd=="STAT": writer.write(f"+OK {count} 2048\r\n".encode())
                elif cmd.startswith("TOP "):
                    if mode=="unsupported": writer.write(b"-ERR TOP unsupported\r\n")
                    elif mode=="oversized": writer.write(b"+OK\r\n"+b"X: data\r\n"*1002+b".\r\n")
                    else: writer.write(b"+OK\r\nFrom: =?UTF-8?B?5aSq6YOO?= <test@example.invalid>\r\nSubject: =?UTF-8?Q?hello_?=\r\n =?UTF-8?Q?world?=\r\n..X-Test: dot-stuffed\r\n\r\n.\r\n")
                elif cmd=="QUIT": writer.write(b"+OK bye\r\n"); await writer.drain(); break
                else: raise AssertionError(cmd)
                await writer.drain()
        except (ConnectionResetError,BrokenPipeError): pass
        finally: writer.close()
    server=await asyncio.start_server(serve,"127.0.0.1",0)
    async with server:
        port=server.sockets[0].getsockname()[1]
        process=await asyncio.create_subprocess_exec(str(PROBE),str(port),stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE)
        out,err=await asyncio.wait_for(process.communicate(),10)
    text=out.decode().strip()
    if mode=="oversized": assert text.startswith("ERROR:"),text
    else:
        value=json.loads(text); assert value["count"]==count
        expected=0 if mode=="unsupported" else min(count,20)
        assert len(value["headers"])==expected,value
        if expected:
            assert value["headers"][0]["sender"]=="太郎 <test@example.invalid>"
            assert value["headers"][0]["subject"]=="hello world"
        assert commands.count("TOP")== (1 if mode=="unsupported" else expected),commands
        assert commands[-1]=="QUIT"
    assert not any(x in commands for x in ["RETR","DELE"])
    print(f"PASS POP3 {mode}: count={count}, TOP requests={commands.count('TOP')}")
async def main():
    for mode,count in [("headers",2),("unsupported",4),("headers",25),("oversized",1)]: await scenario(mode,count)
asyncio.run(main())
