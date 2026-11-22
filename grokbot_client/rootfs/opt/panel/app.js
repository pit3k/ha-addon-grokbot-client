(function () {
  "use strict";

  var statusEl = document.getElementById("status");
  var accountEl = document.getElementById("account");
  var link = document.getElementById("signin-link");
  var qr = document.getElementById("qr");
  var urlInput = document.getElementById("login-url");
  var copy = document.getElementById("copy");
  var signout = document.getElementById("signout");
  var lastUrl = "";
  var wasWaiting = false;
  var qrTimer = 0;

  function show(el, on) {
    el.hidden = !on;
  }

  function loadQr() {
    qr.src = "qr.svg?t=" + Date.now();
  }

  qr.addEventListener("error", function () {
    if (qr.hidden) {
      return;
    }
    clearTimeout(qrTimer);
    qrTimer = setTimeout(loadQr, 1000);
  });

  function render(data) {
    var state = data.state || "";
    var url = data.login_url || "";
    var connected = state === "connected" || state === "restarting";
    var waiting = Boolean(url) && !connected;

    statusEl.textContent = data.status || "Starting";
    accountEl.textContent = data.email || "";
    show(accountEl, connected && Boolean(data.email));
    show(link, waiting);
    show(qr, waiting);
    show(urlInput, waiting);
    show(copy, waiting);
    show(signout, connected);
    if (!waiting) {
      clearTimeout(qrTimer);
      wasWaiting = false;
      return;
    }
    link.href = url;
    urlInput.value = url;
    if (!wasWaiting || url !== lastUrl) {
      lastUrl = url;
      loadQr();
    }
    wasWaiting = true;
  }

  function refresh() {
    fetch("api/status", { cache: "no-store" })
      .then(function (response) { return response.json(); })
      .then(render)
      .catch(function () {
        statusEl.textContent = "Starting";
        signout.hidden = true;
      });
  }

  copy.addEventListener("click", function () {
    urlInput.select();
    document.execCommand("copy");
  });
  signout.addEventListener("click", function () {
    signout.hidden = true;
    fetch("api/sign-out", { method: "POST", headers: { "X-Grokbot-Panel": "1" } }).finally(refresh);
  });
  refresh();
  setInterval(refresh, 2000);
})();
