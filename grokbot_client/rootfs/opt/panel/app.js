(function () {
  "use strict";

  var statusEl = document.getElementById("status");
  var accountEl = document.getElementById("account");
  var link = document.getElementById("signin-link");
  var qr = document.getElementById("qr");
  var signout = document.getElementById("signout");
  var lastUrl = "";

  function show(el, on) {
    el.hidden = !on;
  }

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
    if (waiting) {
      link.href = url;
      link.textContent = url;
      if (url !== lastUrl) {
        qr.src = "qr.svg?u=" + encodeURIComponent(url);
        lastUrl = url;
      }
    }
    show(signout, connected);
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

  signout.addEventListener("click", function () {
    signout.hidden = true;
    fetch("api/sign-out", { method: "POST", headers: { "X-Grokbot-Panel": "1" } }).finally(refresh);
  });
  refresh();
  setInterval(refresh, 2000);
})();
