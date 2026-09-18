const form = document.querySelector('#validation-form');
const input = document.querySelector('#nar-file');
const dropZone = document.querySelector('#drop-zone');
const selectedFile = document.querySelector('#selected-file');
const fileName = document.querySelector('#file-name');
const fileSize = document.querySelector('#file-size');
const submitButton = document.querySelector('#submit-button');
const progress = document.querySelector('#progress');
const progressMessage = document.querySelector('#progress-message');
const requestError = document.querySelector('#request-error');
const results = document.querySelector('#results');
const maximumBytes = Number(document.body.dataset.maximumBytes);
let selected = null;
const maximumBusyRetries = 2;

const supportLabels = {
    supported: '対応',
    experimental: '試験対応',
    compatibilityLayer: '互換レイヤーが必要',
    unavailable: '非対応',
    unknown: '判定不能',
};

const executionLabels = {
    builtIn: 'Utatane内蔵',
    dynamicLibrary: 'macOS用ライブラリ',
    windowsDLL: 'Windows DLL',
    executable: '外部プログラム',
};

const runtimeLabels = {
    none: '追加設定なし',
    wine: 'Wineが必要',
    configuredExecutable: '実行ファイルの設定が必要',
};

function formatBytes(bytes) {
    if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function showError(message) {
    requestError.textContent = message;
    requestError.hidden = false;
}

function chooseFile(file) {
    requestError.hidden = true;
    results.hidden = true;
    if (!file) {
        selected = null;
        selectedFile.hidden = true;
        return;
    }
    if (file.size > maximumBytes) {
        input.value = '';
        selected = null;
        selectedFile.hidden = true;
        showError(`ファイルサイズは${formatBytes(maximumBytes)}までです。`);
        return;
    }
    selected = file;
    fileName.textContent = file.name;
    fileSize.textContent = formatBytes(file.size);
    selectedFile.hidden = false;
}

input.addEventListener('change', () => chooseFile(input.files?.[0]));

for (const eventName of ['dragenter', 'dragover']) {
    dropZone.addEventListener(eventName, (event) => {
        event.preventDefault();
        dropZone.classList.add('is-dragging');
    });
}

for (const eventName of ['dragleave', 'drop']) {
    dropZone.addEventListener(eventName, (event) => {
        event.preventDefault();
        dropZone.classList.remove('is-dragging');
    });
}

dropZone.addEventListener('drop', (event) => chooseFile(event.dataTransfer?.files?.[0]));

form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!selected) {
        showError('NARファイルを選択してください。');
        return;
    }

    requestError.hidden = true;
    results.hidden = true;
    progress.hidden = false;
    submitButton.disabled = true;
    progressMessage.textContent = 'NARファイルを検査しています。';
    const file = selected;

    try {
        for (let attempt = 0; attempt <= maximumBusyRetries; attempt += 1) {
            const body = new FormData();
            body.append('file', file, file.name);
            const response = await fetch('/api/v1/validate', { method: 'POST', body });
            const payload = await response.json().catch(() => null);
            const busy = response.status === 429;
            if (busy && attempt < maximumBusyRetries) {
                const retryAfter = retryAfterSeconds(response.headers.get('Retry-After'));
                progressMessage.textContent = `混雑しています。${retryAfter}秒後に再試行します。`;
                await wait(retryAfter * 1000);
                progressMessage.textContent = 'NARファイルを再送しています。';
                continue;
            }
            if (!response.ok || !payload?.ok) {
                if (busy) {
                    throw new Error(payload?.error?.message || 'アクセスが集中しています。しばらく待って再試行してください。');
                }
                throw new Error(payload?.error?.message || '検査結果を受け取れませんでした。');
            }
            renderReport(payload.report, payload.requestId);
            return;
        }
    } catch (error) {
        showError(error instanceof Error ? error.message : '検査に失敗しました。');
    } finally {
        progress.hidden = true;
        submitButton.disabled = false;
    }
});

function retryAfterSeconds(value) {
    const seconds = Number(value);
    return Number.isFinite(seconds) ? Math.min(30, Math.max(1, Math.round(seconds))) : 5;
}

function wait(milliseconds) {
    return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function renderReport(report, requestId) {
    const diagnostics = Array.isArray(report.diagnostics) ? report.diagnostics : [];
    const errors = diagnostics.filter((item) => item.severity === 'error').length;
    const warnings = diagnostics.filter((item) => item.severity === 'warning').length;
    const assessment = report.shioriAssessment || null;

    document.querySelector('#ghost-name').textContent = report.ghostName || '取得できませんでした';
    document.querySelector('#summary-text').textContent = errors === 0
        ? (warnings === 0 ? '問題は見つかりませんでした。' : `警告が${warnings}件あります。`)
        : `エラーが${errors}件、警告が${warnings}件あります。`;

    const state = document.querySelector('#result-state');
    state.textContent = errors === 0 ? '検査完了' : '要確認';
    state.dataset.state = errors === 0 ? 'passed' : 'failed';

    document.querySelector('#shiori-name').textContent = assessment?.displayName || report.shiori || '判定できませんでした';
    const badge = document.querySelector('#support-badge');
    const support = assessment?.supportStatus || 'unknown';
    badge.textContent = supportLabels[support] || supportLabels.unknown;
    badge.dataset.support = support;

    const detailRows = [
        ['モジュール', assessment?.macOSModuleFilename || assessment?.declaredModuleFilename],
        ['実行方式', executionLabels[assessment?.execution] || assessment?.execution],
        ['追加要件', runtimeLabels[assessment?.runtimeRequirement] || assessment?.runtimeRequirement],
    ].filter(([, value]) => value);
    const details = document.querySelector('#shiori-details');
    details.replaceChildren(...detailRows.flatMap(([term, value]) => {
        const dt = document.createElement('dt');
        const dd = document.createElement('dd');
        dt.textContent = term;
        dd.textContent = value;
        return [dt, dd];
    }));

    const diagnosticCount = document.querySelector('#diagnostic-count');
    diagnosticCount.textContent = `エラー ${errors}件・警告 ${warnings}件`;
    const container = document.querySelector('#diagnostics');
    if (diagnostics.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'diagnostic-empty';
        empty.textContent = '問題は見つかりませんでした。';
        container.replaceChildren(empty);
    } else {
        container.replaceChildren(...diagnostics.map(renderDiagnostic));
    }

    document.querySelector('#request-id').textContent = `Request ID: ${requestId}`;
    results.hidden = false;
    results.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function renderDiagnostic(item) {
    const row = document.createElement('article');
    row.className = 'diagnostic-row';
    row.dataset.severity = item.severity;
    const mark = document.createElement('span');
    mark.className = 'diagnostic-mark';
    mark.textContent = item.severity === 'error' ? '×' : '!';
    const content = document.createElement('div');
    const message = document.createElement('strong');
    message.textContent = item.message || item.code;
    const location = document.createElement('span');
    const line = item.line ? `:${item.line}` : '';
    location.textContent = `${item.path || 'NAR'}${line} · ${item.code || ''}`;
    content.append(message, location);
    row.append(mark, content);
    return row;
}
