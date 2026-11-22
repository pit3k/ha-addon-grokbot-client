(function () {
  "use strict";

  var statusEl = document.getElementById("status");
  var accountEl = document.getElementById("account");
  var signinBlock = document.getElementById("signin-block");
  var signinLink = document.getElementById("signin-link");
  var signinStart = document.getElementById("signin-start");
  var signout = document.getElementById("signout");
  var qr = document.getElementById("qr");
  var urlInput = document.getElementById("login-url");
  var detailEl = document.getElementById("detail");
  var errorEl = document.getElementById("error");
  var versionEl = document.getElementById("version");
  var lastUrl = "";
  var busy = false;

  function show(el, on) {
    el.hidden = !on;
  }

  function text(el, value) {
    el.textContent = value || "";
  }

  function renderCode(url) {
    qr.replaceChildren();
    if (!url || typeof QRCode !== "function") {
      show(qr, false);
      return;
    }
    try {
      show(qr, true);
      new QRCode(qr, {
        text: url,
        width: 200,
        height: 200,
        correctLevel: QRCode.CorrectLevel.L
      });
    } catch (err) {
      show(qr, false);
    }
  }

  function render(data) {
    var state = data.state || "signed_out";
    var url = data.login_url || "";
    statusEl.dataset.state = state;
    text(statusEl, data.status || "Not signed in");
    text(accountEl, data.email ? "Account " + data.email : "");
    show(accountEl, Boolean(data.email) && state === "connected");
    text(detailEl, data.detail || "");
    show(detailEl, Boolean(data.detail));
    text(errorEl, data.error || "");
    show(errorEl, Boolean(data.error));
    text(versionEl, data.version ? "Client " + data.version : "");

    var waiting = state === "waiting" && url;
    show(signinBlock, waiting);
    if (waiting) {
      signinLink.href = url;
      urlInput.value = url;
      if (url !== lastUrl) {
        renderCode(url);
        lastUrl = url;
      }
    } else if (url !== lastUrl) {
      lastUrl = "";
      qr.replaceChildren();
    }

    var preparing = state === "waiting" && !url;
    show(signinStart, state === "signed_out" || state === "starting" || preparing);
    signinStart.disabled = busy || preparing;
    text(signinStart, preparing ? "Preparing sign-in…" : "Sign in");
    show(signout, state === "waiting" || state === "connected" || state === "restarting");
    signout.disabled = busy;
  }

  function post(path) {
    busy = true;
    signinStart.disabled = true;
    signout.disabled = true;
    return fetch(path, {
      method: "POST",
      headers: { "X-Grokbot-Panel": "1" }
    }).finally(function () {
      busy = false;
      refresh();
    });
  }

  function refresh() {
    return fetch("api/status", { cache: "no-store" })
      .then(function (response) { return response.json(); })
      .then(render)
      .catch(function () {
        render({
          state: "signed_out",
          status: "Not signed in",
          error: "The panel could not read the client status."
        });
      });
  }

  signinStart.addEventListener("click", function () { post("api/sign-in"); });
  signout.addEventListener("click", function () { post("api/sign-out"); });
  refresh();
  setInterval(refresh, 2000);
})();
