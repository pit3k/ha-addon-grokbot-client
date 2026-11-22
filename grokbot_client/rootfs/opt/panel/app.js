(function () {
  "use strict";

  var statusEl = document.getElementById("status");
  var accountEl = document.getElementById("account");
  var block = document.getElementById("signin-block");
  var link = document.getElementById("signin-link");
  var start = document.getElementById("signin-start");
  var signout = document.getElementById("signout");
  var qr = document.getElementById("qr");
  var urlInput = document.getElementById("login-url");
  var detailEl = document.getElementById("detail");
  var errorEl = document.getElementById("error");
  var versionEl = document.getElementById("version");
  var lastUrl = "";

  function show(el, on) {
    el.hidden = !on;
  }

  function render(data) {
    var state = data.state || "";
    var url = data.login_url || "";
    var connected = state === "connected" || state === "restarting";
    var waiting = state === "waiting" && url;

    statusEl.textContent = data.status || "Starting";
    accountEl.textContent = data.email ? "Account " + data.email : "";
    show(accountEl, Boolean(data.email) && connected);
    detailEl.textContent = data.detail || "";
    show(detailEl, Boolean(data.detail));
    errorEl.textContent = data.error || "";
    show(errorEl, Boolean(data.error));
    versionEl.textContent = data.version ? "Client " + data.version : "";

    show(block, waiting);
    if (waiting) {
      link.href = url;
      urlInput.value = url;
      if (url !== lastUrl) {
        qr.src = "qr.svg?u=" + encodeURIComponent(url);
        lastUrl = url;
      }
    }
    show(qr, waiting);
    show(start, state === "signed_out" || state === "starting");
    show(signout, waiting || connected);
  }

  function post(path) {
    start.hidden = true;
    signout.disabled = true;
    fetch(path, { method: "POST", headers: { "X-Grokbot-Panel": "1" } }).finally(refresh);
  }

  function refresh() {
    fetch("api/status", { cache: "no-store" })
      .then(function (response) { return response.json(); })
      .then(render)
      .catch(function () {
        statusEl.textContent = "Starting";
        start.hidden = true;
      });
  }

  start.addEventListener("click", function () { post("api/sign-in"); });
  signout.addEventListener("click", function () { post("api/sign-out"); });
  refresh();
  setInterval(refresh, 2000);
})();
