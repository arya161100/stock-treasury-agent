(() => {
  const $ = (id) => document.getElementById(id);
  const cfg = window.STOCK_TREASURY_CONFIG || {};

  const PREVIEW_ABI = [
    "function preview() view returns ((address usdc,address owner,address agent,address router,uint16 allocationBps,uint256 operatingReserveTarget,uint256 perTxCap,uint256 dailyCap,uint256 dailyUsed,uint64 dailyWindow,bool paused,bool policySet,uint256 usdcBalance,uint256 investable,uint256 reservedEffective,uint256 retained,uint256 lastAccounted))",
  ];
  // Manual selector + decode without a library, so GitHub Pages has zero deps.
  // preview() = keccak256("preview()")[0:4]
  const PREVIEW_SEL = "0x0d8e6e2c"; // placeholder, computed at runtime below if we have a snapshot

  function fmt6(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return String(v);
    return (n / 1e6).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " USDC";
  }
  function alreadyHuman(s) {
    if (typeof s === "string" && s.includes(".")) return s + " USDC";
    return fmt6(s);
  }

  function render(snap) {
    const d = snap.deployment || cfg;
    const p = snap.preview || {};
    $("meta").innerHTML = [
      `<div>${escapeHtml(d.network || "unknown")} · chain ${escapeHtml(String(d.chainId || ""))}</div>`,
      `<div>vault ${short(d.vault)}</div>`,
      `<div>usdc  ${short(d.usdc)}</div>`,
      d.explorer && d.vault
        ? `<div><a href="${d.explorer}/address/${d.vault}" target="_blank" rel="noopener">explorer</a></div>`
        : "",
    ].join("");

    const bps = p.allocationBps ?? (d.policy && d.policy.allocationBps) ?? 0;
    $("bps-label").textContent = (Number(bps) / 100).toString();

    const reserve = Number(p.reservedEffective ?? 0);
    const retained = Number(p.retained ?? 0);
    const investable = Number(p.investable ?? 0);
    const total = Number(p.usdcBalance ?? reserve + retained + investable);
    const denom = total || 1;
    const bar = $("bar");
    bar.children[0].style.flex = String(reserve / denom);
    bar.children[1].style.flex = String(retained / denom);
    bar.children[2].style.flex = String(investable / denom);
    $("v-reserve").textContent = human(p.reservedEffective, p.operatingReserveTarget);
    $("v-retained").textContent = human(p.retained);
    $("v-investable").textContent = human(p.investable);
    $("v-total").textContent = human(p.usdcBalance);

    $("policy").innerHTML = [
      row("allocation", `${Number(bps) / 100}% of surplus`),
      row("reserve target", human(p.operatingReserveTarget)),
      row("per-tx cap", human(p.perTxCap)),
      row("daily cap", human(p.dailyCap) + ` (used ${human(p.dailyUsed)})`),
      row("paused", String(!!p.paused)),
      row("agent", short(p.agent || d.agent)),
      row("owner", short(p.owner || d.owner)),
      row("router", short(p.router || d.router)),
    ].join("");

    const holdings = snap.holdings || [];
    const stocks = d.stocks || [];
    if (!holdings.length) {
      $("holdings").innerHTML = `<p class="hint">No holdings yet. Mock tokens: ${(stocks.map((s) => s.symbol).join(", ")) || "—"}.</p>`;
    } else {
      $("holdings").innerHTML = holdings
        .map((h) => {
          const meta = stocks.find((s) => (s.address || "").toLowerCase() === (h.token || "").toLowerCase());
          const sym = (meta && meta.symbol) || short(h.token);
          return `<div class="holding"><span>${escapeHtml(sym)}</span><span>${escapeHtml(h.human || h.raw)}</span></div>`;
        })
        .join("");
    }

    const rejections = (snap.log || []).filter((e) => e.rejected || e.ok === false);
    $("rejections").innerHTML = rejections.length
      ? rejections
          .map(
            (e) =>
              `<div class="row"><span class="bad">✕</span><div><div class="bad">${escapeHtml(e.error || "rejected")}</div><div class="muted">${escapeHtml(e.step || "")} · attempted ${escapeHtml(e.attempted || "")} raw USDC units</div></div></div>`
          )
          .join("")
      : `<div class="row"><span>·</span><div class="muted">No rejections recorded yet. Run the agent loop.</div></div>`;

    $("log").innerHTML = (snap.log || [])
      .map((e) => {
        const mark = e.rejected || e.ok === false ? "✕" : "✓";
        const cls = e.rejected || e.ok === false ? "bad" : "ok";
        const tx = e.tx ? short(e.tx) : "";
        return `<div class="row"><span class="${cls}">${mark}</span><div><div>${escapeHtml(e.step || "")}${tx ? ` · <span class="muted">${escapeHtml(tx)}</span>` : ""}</div><div class="muted">${escapeHtml(e.error || "")}</div></div></div>`;
      })
      .join("") || `<div class="row"><span>·</span><div class="muted">No run log. Open snapshot.json after scripts/demo.sh.</div></div>`;
  }

  function human(v, fallback) {
    if (v == null || v === "") v = fallback;
    if (v == null) return "—";
    if (typeof v === "string" && v.includes(".")) return v + " USDC";
    return fmt6(v);
  }
  function row(k, v) {
    return `<dt>${escapeHtml(k)}</dt><dd>${v}</dd>`;
  }
  function short(a) {
    if (!a) return "—";
    const s = String(a);
    return s.length > 16 ? s.slice(0, 8) + "…" + s.slice(-6) : s;
  }
  function escapeHtml(s) {
    return String(s ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  async function load() {
    try {
      const res = await fetch("./snapshot.json", { cache: "no-store" });
      if (res.ok) {
        render(await res.json());
        return;
      }
    } catch (_) {}
    // Fallback: empty shell from config.js so the page still explains the rules.
    render({ deployment: cfg, preview: { allocationBps: (cfg.policy && cfg.policy.allocationBps) || 7000 }, holdings: [], log: [] });
  }

  load();
})();
