(function () {
  "use strict";

  var statusEl = document.getElementById("status");
  var accountEl = document.getElementById("account");
  var link = document.getElementById("signin-link");
  var qr = document.getElementById("qr");
  var row = document.getElementById("link-row");
  var urlInput = document.getElementById("login-url");
  var copy = document.getElementById("copy");
  var signout = document.getElementById("signout");
  var permission = document.getElementById("permission");
  var lastUrl = "";
  var wasWaiting = false;
  var permissionSet = false;
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
    show(row, waiting);
    show(permission, !connected);
    show(signout, connected);
    if (!connected && !permissionSet) {
      var inputs = permission.querySelectorAll("input");
      var i;
      for (i = 0; i < inputs.length; i++) {
        inputs[i].checked = inputs[i].value === (data.permission || "");
      }
      permissionSet = true;
    }
    if (connected) {
      permissionSet = false;
    }
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
    fetch("cgi-bin/status", { cache: "no-store" })
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
  permission.addEventListener("change", function (event) {
    permissionSet = true;
    fetch("cgi-bin/permission", {
      method: "POST",
      headers: { "X-Grokbot-Panel": "1" },
      body: event.target.value
    });
  });
  signout.addEventListener("click", function () {
    signout.hidden = true;
    fetch("cgi-bin/sign-out", { method: "POST", headers: { "X-Grokbot-Panel": "1" } }).finally(refresh);
  });
  refresh();
  setInterval(refresh, 2000);
})();
