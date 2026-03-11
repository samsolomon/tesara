(function () {
  const term = new Terminal({
    allowProposedApi: false,
    convertEol: false,
    cursorBlink: true,
    fontFamily: 'SF Mono, Menlo, ui-monospace, monospace',
    fontSize: 13,
    scrollback: 5000,
    theme: {
      background: '#0b1020',
      foreground: '#e5e7eb'
    }
  });
  const fitAddon = new FitAddon.FitAddon();

  const root = document.getElementById('terminal');
  let lastSize = { cols: 0, rows: 0 };
  term.open(root);
  term.loadAddon(fitAddon);
  term.focus();

  function postMessage(name, body) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
      window.webkit.messageHandlers[name].postMessage(body);
    }
  }

  function fitTerminal() {
    fitAddon.fit();
    const nextSize = { cols: term.cols, rows: term.rows };
    if (nextSize.cols !== lastSize.cols || nextSize.rows !== lastSize.rows) {
      lastSize = nextSize;
      postMessage('terminalResize', nextSize);
    }
  }

  term.onData(function (data) {
    postMessage('terminalInput', data);
  });

  const resizeObserver = new ResizeObserver(function () {
    fitTerminal();
  });
  resizeObserver.observe(root);

  window.addEventListener('resize', fitTerminal);

  window.tesaraRender = function (payload) {
    document.body.style.background = payload.theme.background;
    term.options.theme = {
      background: payload.theme.background,
      foreground: payload.theme.foreground,
      cursor: payload.theme.cursor,
      cursorAccent: payload.theme.cursorText,
      selectionBackground: payload.theme.selectionBackground,
      selectionForeground: payload.theme.selectionForeground || undefined,
      black: payload.theme.black,
      red: payload.theme.red,
      green: payload.theme.green,
      yellow: payload.theme.yellow,
      blue: payload.theme.blue,
      magenta: payload.theme.magenta,
      cyan: payload.theme.cyan,
      white: payload.theme.white,
      brightBlack: payload.theme.brightBlack,
      brightRed: payload.theme.brightRed,
      brightGreen: payload.theme.brightGreen,
      brightYellow: payload.theme.brightYellow,
      brightBlue: payload.theme.brightBlue,
      brightMagenta: payload.theme.brightMagenta,
      brightCyan: payload.theme.brightCyan,
      brightWhite: payload.theme.brightWhite
    };
    term.options.fontFamily = payload.fontFamily;
    term.options.fontSize = payload.fontSize;
    fitTerminal();

    if (payload.replace) {
      term.reset();
      if (payload.content) {
        term.write(payload.content);
      }
      fitTerminal();
      return;
    }

    if (payload.content) {
      term.write(payload.content);
    }
  };
})();
