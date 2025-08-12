<script>
(() => {
  // ======== STATE ========
  let wallets = [];
  let categories = [];
  let purposes = [];
  let txCache = [];
  let walletBalances = []; // [{wallet, balance, type}]
  let _budgetCache = [];
  let _goalsCache = [];

  // ======== ELEMENTS ========
  const setupView = document.getElementById('setupView');
  const dashboardView = document.getElementById('dashboardView');
  const historyView   = document.getElementById('historyView');
  const reportView    = document.getElementById('reportView');

  const btnTabDashboard = document.getElementById('btnTabDashboard');
  const btnTabHistory   = document.getElementById('btnTabHistory');
  const btnTabReport    = document.getElementById('btnTabReport');
  const btnSetupOpen    = document.getElementById('btnSetupOpen');

  const setupMsg  = document.getElementById('setupMsg');

  // Quick Add form (Dashboard)
  const form    = document.getElementById('txForm');
  const dateInp = document.getElementById('date');
  const subSel  = document.getElementById('subcategory');
  const walSel  = document.getElementById('wallet');
  const amtInp  = document.getElementById('amount');
  const transferWrap = document.getElementById('transferWrap');
  const transferSel  = document.getElementById('transferTo');
  const expSel  = document.getElementById('expensePurpose');
  const noteInp = document.getElementById('note');
  const noteDL  = document.getElementById('noteOptions');
  const descInp = document.getElementById('description');

  // History & Reports
  const txList = document.getElementById('txList');
  const search = document.getElementById('search');
  const budgetTbody = document.getElementById('budgetTbody');
  const goalsWrap   = document.getElementById('goalsWrap');

  // Dashboard widgets
  const walletBalancesWrap = document.getElementById('walletBalancesWrap');
  const lastTxWrap = document.getElementById('lastTxWrap');
  const budgetOverviewWrap = document.getElementById('budgetOverviewWrap');
  const btnGotoHistory = document.getElementById('btnGotoHistory');
  const btnRefreshHeader = document.getElementById('btnRefreshHeader');
  const netWorthTotal = document.getElementById('netWorthTotal'); // mungkin belum ada; skrip handle otomatis

  // Setup master forms
  const masterFormWrap = document.getElementById('masterFormWrap');
  const btnOpenAccount  = document.getElementById('btnOpenAccount');
  const btnOpenWallet   = document.getElementById('btnOpenWallet');
  const btnOpenCategory = document.getElementById('btnOpenCategory');
  const btnOpenGoals    = document.getElementById('btnOpenGoals');

  // ======== Toast ========
  const toast = document.createElement('div');
  toast.id = 'toastNotif';
  toast.style.cssText = `
    position: fixed; bottom: 20px; right: 20px; background:#10b981; color:white;
    padding:10px 15px; border-radius:8px; font-size:14px; display:none; z-index:9999;
  `;
  document.body.appendChild(toast);
  function showToast(msg){ toast.textContent = msg; toast.style.display='block'; setTimeout(()=>toast.style.display='none',3000); }

  // ======== NAV ========
  function showOnly(viewEl){
    [setupView, dashboardView, historyView, reportView].forEach(v => v && v.classList.add('hidden'));
    viewEl && viewEl.classList.remove('hidden');
  }
  btnTabDashboard?.addEventListener('click', () => { showOnly(dashboardView); });
  btnTabHistory  ?.addEventListener('click', () => { showOnly(historyView); renderTransactions(); });
  btnTabReport   ?.addEventListener('click', () => { showOnly(reportView); renderBudgetSummary(_budgetCache); renderGoalsProgress(_goalsCache); });
  btnSetupOpen   ?.addEventListener('click', () => { showOnly(setupView); masterFormWrap.innerHTML=''; });

  btnGotoHistory?.addEventListener('click', () => { btnTabHistory?.click(); });
  btnRefreshHeader?.addEventListener('click', () => { bootstrap(); showToast('✅ Data diperbarui'); });

  // ======== SETUP: Buat DB ========
  document.getElementById('btnCreateNew')?.addEventListener('click', () => {
    setupMsg.textContent = 'Membuat database di Drive Bung...';
    google.script.run.withSuccessHandler(() => {
      setupMsg.textContent = 'DB dibuat & terhubung. Memuat aplikasi...';
      bootstrap();
    }).withFailureHandler(err => {
      setupMsg.textContent = (err && err.message) || 'Gagal membuat DB.';
    }).createNewDb();
  });

  // ======== BOOTSTRAP ========
  function bootstrap() {
    gs('getInitialData').then(data => {
      wallets        = data.wallets || [];
      categories     = data.categories || [];
      purposes       = data.purposes || [];
      txCache        = data.transactions || [];
      _budgetCache   = data.budgetSummary || [];
      _goalsCache    = data.goalsProgress || [];
      walletBalances = data.walletBalances || [];

      // Fill selects for quick add
      const subOptions = (categories||[]).map(x => x.Subcategory).filter(s => s && s !== 'Transfer-In');
      fillSelect(subSel, subOptions);
      fillSelect(walSel, (wallets||[]).map(x => x.Wallet));
      fillSelect(transferSel, (wallets||[]).map(x => x.Wallet));
      fillDatalist(noteDL, data.notes || []);
      fillSelect(expSel, purposes);

      renderDashboard();
      dateInp && (dateInp.valueAsNumber = Date.now() - (new Date()).getTimezoneOffset()*60000);
      showOnly(dashboardView);
    }).catch(err => { console.log('Bootstrap gagal:', err); showOnly(setupView); });
  }

  function refreshAllData() {
    gs('getInitialData').then(data => {
      txCache        = data.transactions || [];
      _budgetCache   = data.budgetSummary || [];
      _goalsCache    = data.goalsProgress || [];
      walletBalances = data.walletBalances || [];
      renderTransactions();
      renderBudgetSummary(_budgetCache);
      renderGoalsProgress(_goalsCache);
      renderDashboardCards();
    });
  }

  // ======== UTIL KONEKSI GAS & DOM ========
  function gs(fnName, arg) {
    return new Promise((resolve, reject) => {
      const call = google.script.run.withSuccessHandler(resolve).withFailureHandler(reject);
      (arg === undefined) ? call[fnName]() : call[fnName](arg);
    });
  }
  function fillSelect(sel, arr) {
    if (!sel) return;
    sel.innerHTML = '';
    (arr||[]).forEach(v => { const o = document.createElement('option'); o.value = v; o.textContent = v; sel.appendChild(o); });
  }
  function fillDatalist(dl, arr) {
    if (!dl) return;
    dl.innerHTML = '';
    (arr||[]).forEach(v => { const o = document.createElement('option'); o.value = v; dl.appendChild(o); });
  }
  function formatMoney(n){ return (new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0})).format(n||0); }
  function safeDate(v){ try{ const d=new Date(v); return isFinite(d)? d.toLocaleDateString():'';}catch(_){return '';} }
  function escapeHtml(s){ return String(s||'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m])); }

  // ======== TRANSFER UI ========
  function refreshTransferUI() {
    const isTransferOut = subSel?.value === 'Transfer-Out';
    if (!transferWrap) return;
    transferWrap.classList.toggle('hidden', !isTransferOut);
    if (isTransferOut) {
      const from = walSel?.value;
      [...(transferSel?.options || [])].forEach(o => { o.disabled = (o.value === from); });
      if (transferSel?.value === from) transferSel.value = '';
    }
  }
  subSel?.addEventListener('change', refreshTransferUI);
  walSel?.addEventListener('change', refreshTransferUI);

  // ======== SUBMIT TRANSAKSI (Quick Add) ========
  form?.addEventListener('submit', (ev) => {
    ev.preventDefault();
    const isTO = (subSel.value === 'Transfer-Out');
    const payload = {
      date: dateInp.value,
      subcategory: subSel.value,
      wallet: walSel.value,
      amount: Number(amtInp.value || 0),
      transferTo: isTO ? transferSel.value : '',
      expensePurpose: expSel.value || '',
      note: (noteInp.value || '').trim(),
      description: (descInp.value || '').trim(),
    };
    if (isTO && !payload.transferTo) { alert('Pilih dompet tujuan, Bung.'); return; }
    if (!payload.amount || payload.amount <= 0) { alert('Amount harus > 0.'); return; }

    disableForm(true);
    google.script.run.withSuccessHandler(() => {
      amtInp.value = ''; noteInp.value = ''; descInp.value = '';
      bootstrap(); // refresh total biar Dashboard, Riwayat, Laporan ikut update
      disableForm(false);
      showToast('✅ Transaksi tersimpan');
    }).withFailureHandler(err => { alert((err && err.message) || 'Gagal menyimpan.'); disableForm(false); })
      .addTransaction(payload);
  });
  function disableForm(dis){ form?.querySelectorAll('input,select,button').forEach(el => el.disabled = dis); }

  // ======== HISTORY ========
  function renderTransactions() {
    if (!txList) return;
    const q = (search?.value || '').toLowerCase();
    txList.innerHTML = '';
    const rows = txCache.filter(tx => {
      const line = [
        tx.UniqueID, tx.Wallet, tx.Subcategory, tx.Category,
        safeDate(tx.Date), String(tx.Amount), String(tx.AdjustedAmount),
        tx.Note || '', tx.Description || ''
      ].join(' ').toLowerCase();
      return !q || line.includes(q);
    });
    if (!rows.length) {
      txList.innerHTML = `<div class="text-sm text-slate-500">Belum ada transaksi.</div>`;
      return;
    }
    rows.forEach(tx => {
      const el = document.createElement('div');
      el.className = 'border rounded p-2 text-sm flex items-center justify-between';
      const amt = Number(tx.AdjustedAmount || 0);
      el.innerHTML = `
        <div>
          <div class="font-medium">${safeDate(tx.Date)} — ${escapeHtml(tx.Subcategory)} · ${escapeHtml(tx.Wallet)}</div>
          <div class="text-slate-600">${escapeHtml(tx.Note || tx.Description || '')}</div>
        </div>
        <div class="text-right ${amt < 0 ? 'text-rose-600' : 'text-emerald-600'}">
          ${formatMoney(amt)}
        </div>
      `;
      txList.appendChild(el);
    });
  }
  search?.addEventListener('input', renderTransactions);

  // ======== REPORTS ========
  function renderBudgetSummary(list) {
    if (!budgetTbody) return;
    budgetTbody.innerHTML = '';
    // pastikan transfer tidak tampil, bila backend lama masih menyertakan
    const rows = (list || []).filter(r => String(r.category||'').toLowerCase() !== 'transfer');
    rows.forEach(r => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="p-2">${escapeHtml(r.category || '')}</td>
        <td class="p-2">${escapeHtml(r.subcategory || '')}</td>
        <td class="p-2 text-right">${formatMoney(r.spent || 0)}</td>
        <td class="p-2 text-right">${formatMoney(r.remaining || 0)}</td>
      `;
      budgetTbody.appendChild(tr);
    });
  }
  function renderGoalsProgress(list) {
    if (!goalsWrap) return;
    goalsWrap.innerHTML = '';
    (list || []).forEach(g => {
      const pct = Math.max(0, Math.min(1, Number(g.completion || 0)));
      const item = document.createElement('div');
      item.innerHTML = `
        <div class="flex justify-between text-sm">
          <div class="font-medium">${escapeHtml(g.goal || '')}</div>
          <div>${formatMoney(g.progress || 0)} / ${formatMoney(g.needed || 0)}</div>
        </div>
        <div class="w-full bg-slate-200 rounded h-2 overflow-hidden">
          <div class="bg-emerald-500 h-2" style="width:${(pct * 100).toFixed(0)}%"></div>
        </div>`;
      goalsWrap.appendChild(item);
    });
  }

  // ======== DASHBOARD ========
  function renderDashboard(){
    renderDashboardCards();
    renderLastTx();
    renderBudgetOverview();
    refreshTransferUI();
  }

  // Buat/atur header Net Worth secara otomatis bila index belum diubah
  function ensureNetWorthHeader(){
    if (!walletBalancesWrap) return { totalEl: null, titleEl: null };
    const section = walletBalancesWrap.closest('section');
    if (!section) return { totalEl: null, titleEl: null };

    // Jika sudah ada elemen total, gunakan itu
    let totalEl = section.querySelector('#netWorthTotal');
    let titleEl = section.querySelector('h2');

    // Jika belum ada layout fleksibel, bentuk sekarang
    const existingFlex = section.querySelector('#netWorthHeaderWrap');
    if (!existingFlex && titleEl) {
      const flex = document.createElement('div');
      flex.id = 'netWorthHeaderWrap';
      flex.className = 'flex items-center justify-between mb-3';
      titleEl.replaceWith(flex);
      titleEl.classList.remove('mb-3');
      flex.appendChild(titleEl);
      totalEl = document.createElement('div');
      totalEl.id = 'netWorthTotal';
      totalEl.className = 'text-lg font-semibold';
      flex.appendChild(totalEl);
    }

    // Jika total belum ada karena index lama, buat elemen kecil di kanan atas
    if (!totalEl) {
      totalEl = document.createElement('div');
      totalEl.id = 'netWorthTotal';
      totalEl.className = 'text-lg font-semibold';
      // letakkan sebelum grid balance
      section.insertBefore(totalEl, walletBalancesWrap);
    }
    return { totalEl, titleEl: section.querySelector('h2') };
  }

  function renderDashboardCards(){
    if (!walletBalancesWrap) return;

    walletBalancesWrap.innerHTML = '';
    const sorted = (walletBalances||[]).slice().sort((a,b)=>a.wallet.localeCompare(b.wallet));

    // siapkan header Net Worth (judul + total)
    const { totalEl, titleEl } = ensureNetWorthHeader();
    if (titleEl) titleEl.textContent = 'Net Worth';

    if (!sorted.length) {
      walletBalancesWrap.innerHTML = `<div class="text-sm text-slate-500">Belum ada saldo.</div>`;
      if (totalEl){ totalEl.textContent = formatMoney(0); totalEl.classList.remove('text-rose-700','text-emerald-700'); }
      return;
    }

    // hitung total net worth
    let net = 0;
    sorted.forEach(w => {
      let val = Number(w.balance || 0);
      // guard opsional: kalau liabilities tercatat positif, balikkan tandanya agar net worth benar
      if (String(w.type||'') === 'Liabilities' && val > 0) val = -val;
      net += val;

      const el = document.createElement('div');
      const neg = Number(w.balance||0) < 0;
      el.className = 'border rounded p-3 flex items-center justify-between';
      el.innerHTML = `
        <div>
          <div class="font-medium">${escapeHtml(w.wallet)}</div>
          <div class="text-xs text-slate-500">${escapeHtml(w.type || '')}</div>
        </div>
        <div class="${neg ? 'text-rose-600' : 'text-emerald-600'} font-semibold">${formatMoney(w.balance || 0)}</div>
      `;
      walletBalancesWrap.appendChild(el);
    });

    if (totalEl){
      totalEl.textContent = formatMoney(net);
      totalEl.classList.toggle('text-rose-700', net < 0);
      totalEl.classList.toggle('text-emerald-700', net >= 0);
    }
  }

  function renderLastTx(){
    if (!lastTxWrap) return;
    lastTxWrap.innerHTML = '';
    const rows = (txCache||[]).slice(-5).reverse();
    if (!rows.length) { lastTxWrap.innerHTML = `<div class="text-sm text-slate-500">Belum ada transaksi.</div>`; return; }
    rows.forEach(tx => {
      const amt = Number(tx.AdjustedAmount || 0);
      const el = document.createElement('div');
      el.className = 'border rounded p-2 text-sm flex items-center justify-between';
      el.innerHTML = `
        <div>
          <div class="font-medium">${safeDate(tx.Date)} — ${escapeHtml(tx.Subcategory)} · ${escapeHtml(tx.Wallet)}</div>
          <div class="text-slate-600">${escapeHtml(tx.Note || tx.Description || '')}</div>
        </div>
        <div class="text-right ${amt < 0 ? 'text-rose-600' : 'text-emerald-600'}">${formatMoney(amt)}</div>
      `;
      lastTxWrap.appendChild(el);
    });
  }

  function renderBudgetOverview(){
    if (!budgetOverviewWrap) return;
    budgetOverviewWrap.innerHTML = '';
    // pastikan transfer tidak tampil, walau backend lama masih menyertakan
    const base = (_budgetCache||[]).filter(r => (String(r.category||'').toLowerCase() !== 'transfer'));
    // ambil 5 baris paling “kritis”
    const rows = base.slice().sort((a,b)=> (a.remaining||0) - (b.remaining||0)).slice(0,5);
    if (!rows.length) { budgetOverviewWrap.innerHTML = `<div class="text-sm text-slate-500">Tidak ada data budget.</div>`; return; }
    rows.forEach(r => {
      const total = Number(r.budget||0);
      const spent = Math.abs(Number(r.spent||0)); // spent negatif → ambil abs
      const pct = total > 0 ? Math.min(1, spent/total) : 0;
      const item = document.createElement('div');
      item.innerHTML = `
        <div class="flex justify-between text-sm mb-1">
          <div class="font-medium">${escapeHtml(r.subcategory || '')}</div>
          <div>${formatMoney(spent)} / ${formatMoney(total)}</div>
        </div>
        <div class="w-full bg-slate-200 rounded h-2 overflow-hidden">
          <div class="bg-emerald-500 h-2" style="width:${(pct*100).toFixed(0)}%"></div>
        </div>
      `;
      budgetOverviewWrap.appendChild(item);
    });
  }

  // ======== MASTER VIEW SWITCHER (TAB) ========
  function renderIntoMaster(html) {
    masterFormWrap.innerHTML = '';
    const wrapper = document.createElement('div');
    wrapper.innerHTML = html.trim();
    masterFormWrap.appendChild(wrapper.firstElementChild);
  }
  const MASTER_BTNS = [btnOpenAccount, btnOpenWallet, btnOpenCategory, btnOpenGoals];
  function setActiveMaster(btn){
    MASTER_BTNS.forEach(b => {
      b && b.classList.remove('font-semibold','underline','decoration-white','decoration-[3px]','underline-offset-8');
      b && b.classList.add('text-white');
      b && b.setAttribute('aria-selected','false');
    });
    btn && btn.classList.add('font-semibold','underline','decoration-white','decoration-[3px]','underline-offset-8','text-white');
    btn && btn.setAttribute('aria-selected','true');
  }
  function openMaster(section){
    switch(section){
      case 'account':  renderAccountForm();  setActiveMaster(btnOpenAccount);  break;
      case 'wallet':   renderWalletForm();   setActiveMaster(btnOpenWallet);   break;
      case 'category': renderCategoryForm(); setActiveMaster(btnOpenCategory); break;
      case 'goals':    renderGoalsForm();    setActiveMaster(btnOpenGoals);    break;
    }
  }
  btnOpenAccount ?.addEventListener('click', () => openMaster('account'));
  btnOpenWallet  ?.addEventListener('click', () => openMaster('wallet'));
  btnOpenCategory?.addEventListener('click', () => openMaster('category'));
  btnOpenGoals   ?.addEventListener('click', () => openMaster('goals'));

  // ——— Account (Expense Purpose) —
  function renderAccountForm() {
    renderIntoMaster(`
      <div id="accountForm" class="border rounded p-3">
        <h4 class="font-medium mb-2">Tambah Expense Purpose</h4>
        <form id="fAccount" class="grid grid-cols-2 gap-3">
          <label class="col-span-2">Expense Purpose
            <input name="expensePurpose" class="mt-1 w-full border rounded p-2" required />
          </label>
          <div class="col-span-2 flex justify-end">
            <button class="px-3 py-2 bg-emerald-600 text-white rounded">Simpan</button>
          </div>
        </form>
        <p id="msgAccount" class="text-sm text-slate-600 mt-2"></p>
      </div>
    `);
    const f = document.getElementById('fAccount'), msg = document.getElementById('msgAccount');
    f.onsubmit = (e) => {
      e.preventDefault();
      const payload = Object.fromEntries(new FormData(f).entries());
      msg.textContent = 'Menyimpan...';
      google.script.run.withSuccessHandler(() => {
        msg.textContent = 'Tersimpan.'; f.reset();
        bootstrap(); showToast('✅ Data diperbarui');
      }).withFailureHandler(err => { msg.textContent = err?.message || 'Gagal.'; })
        .createAccountPurpose(payload);
    };
  }

  // ——— Wallet —
  function renderWalletForm() {
    renderIntoMaster(`
      <div id="walletForm" class="border rounded p-3">
        <h4 class="font-medium mb-2">Tambah Wallet</h4>
        <form id="fWallet" class="grid grid-cols-3 gap-3">
          <label class="col-span-1">Wallet
            <input name="wallet" class="mt-1 w-full border rounded p-2" required />
          </label>
          <label class="col-span-1">Wallet Type
            <select name="walletType" class="mt-1 w-full border rounded p-2" required>
              <option value="Cash & Bank">Cash & Bank</option>
              <option value="Savings/Investments">Savings/Investments</option>
              <option value="Other Asset">Other Asset</option>
              <option value="Liabilities">Liabilities</option>
            </select>
          </label>
          <label class="col-span-1">Wallet Owner
            <select id="walletOwnerSel" name="walletOwner" class="mt-1 w-full border rounded p-2"></select>
          </label>
          <div class="col-span-3 flex justify-end">
            <button class="px-3 py-2 bg-emerald-600 text-white rounded">Simpan</button>
          </div>
        </form>
        <p id="msgWallet" class="text-sm text-slate-600 mt-2"></p>
      </div>
    `);
    const ownerSel = document.getElementById('walletOwnerSel');
    fillSelect(ownerSel, purposes);
    const f = document.getElementById('fWallet'), msg = document.getElementById('msgWallet');
    f.onsubmit = (e) => {
      e.preventDefault();
      const payload = Object.fromEntries(new FormData(f).entries());
      msg.textContent = 'Menyimpan...';
      google.script.run.withSuccessHandler(() => {
        msg.textContent = 'Tersimpan.'; f.reset();
        bootstrap(); showToast('✅ Data diperbarui');
      }).withFailureHandler(err => { msg.textContent = err?.message || 'Gagal.'; })
        .createWallet(payload);
    };
  }

  // ——— Category —
  function renderCategoryForm() {
    renderIntoMaster(`
      <div id="categoryForm" class="border rounded p-3">
        <h4 class="font-medium mb-2">Tambah Category/Subcategory</h4>
        <form id="fCategory" class="grid grid-cols-3 gap-3">
          <label class="col-span-1">Category
            <select id="categorySel" name="categorySel" class="mt-1 w-full border rounded p-2"></select>
          </label>
          <label id="newCatWrap" class="col-span-1 hidden">Category (Baru)
            <input id="newCategory" class="mt-1 w-full border rounded p-2" placeholder="Nama Category Baru" />
          </label>
          <label class="col-span-1">Subcategory
            <input name="subcategory" class="mt-1 w-full border rounded p-2" required />
          </label>
          <label class="col-span-1">Transaction Type
            <select name="transactionType" class="mt-1 w-full border rounded p-2">
              <option>Expense</option><option>Income</option><option>Transfer</option>
            </select>
          </label>
          <div class="col-span-3 flex justify-end">
            <button class="px-3 py-2 bg-emerald-600 text-white rounded">Simpan</button>
          </div>
        </form>
        <p id="msgCategory" class="text-sm text-slate-600 mt-2"></p>
      </div>
    `);
    const catSel = document.getElementById('categorySel');
    const newCatWrap = document.getElementById('newCatWrap');
    const newCatInp  = document.getElementById('newCategory');
    const uniqueCats = Array.from(new Set((categories||[]).map(x => x.Category).filter(Boolean))).sort();
    if (catSel){
      catSel.innerHTML = '';
      const NEW_VAL = '— Tambah Baru… —';
      [...uniqueCats, NEW_VAL].forEach(v => {
        const o = document.createElement('option'); o.value = v; o.textContent = v; catSel.appendChild(o);
      });
      if (uniqueCats.length === 0) catSel.value = NEW_VAL;
      catSel.addEventListener('change', () => {
        const isNew = (catSel.value === NEW_VAL);
        newCatWrap.classList.toggle('hidden', !isNew);
        if (isNew) newCatInp.focus();
      });
      catSel.dispatchEvent(new Event('change'));
    }

    const f = document.getElementById('fCategory'), msg = document.getElementById('msgCategory');
    f.onsubmit = (e) => {
      e.preventDefault();
      const isNew = (catSel.value === '— Tambah Baru… —');
      const category = isNew ? (newCatInp.value || '').trim() : catSel.value;
      if (!category) { msg.textContent = 'Category baru belum diisi.'; return; }
      const fd = new FormData(f);
      const payload = {
        category,
        subcategory: (fd.get('subcategory') || '').trim(),
        transactionType: fd.get('transactionType') || 'Expense',
      };
      if (!payload.subcategory) { msg.textContent = 'Subcategory wajib diisi.'; return; }
      msg.textContent = 'Menyimpan...';
      google.script.run.withSuccessHandler(() => {
        msg.textContent = 'Tersimpan.'; f.reset(); newCatInp.value = '';
        bootstrap(); showToast('✅ Data diperbarui');
      }).withFailureHandler(err => { msg.textContent = err?.message || 'Gagal.'; })
        .createCategory(payload);
    };
  }

  // ——— Goals —
  function renderGoalsForm() {
    renderIntoMaster(`
      <div id="goalsForm" class="border rounded p-3">
        <h4 class="font-medium mb-2">Tambah Goal</h4>
        <form id="fGoal" class="grid grid-cols-3 gap-3">
          <label class="col-span-1">Goal
            <input name="goal" class="mt-1 w-full border rounded p-2" required />
          </label>
          <label class="col-span-1">Owner
            <select id="goalOwnerSel" name="goalOwner" class="mt-1 w-full border rounded p-2"></select>
          </label>
          <label class="col-span-1">Deadline
            <input name="deadline" type="date" class="mt-1 w-full border rounded p-2" />
          </label>
          <label class="col-span-3">Nominal Needed
            <input name="nominalNeeded" type="number" min="0" step="1" class="mt-1 w-full border rounded p-2" />
          </label>
          <div class="col-span-3 flex justify-end">
            <button class="px-3 py-2 bg-emerald-600 text-white rounded">Simpan</button>
          </div>
        </form>
        <p id="msgGoal" class="text-sm text-slate-600 mt-2"></p>
      </div>
    `);
    const ownerSel = document.getElementById('goalOwnerSel');
    fillSelect(ownerSel, purposes);
    const f = document.getElementById('fGoal'), msg = document.getElementById('msgGoal');
    f.onsubmit = (e) => {
      e.preventDefault();
      const payload = Object.fromEntries(new FormData(f).entries());
      msg.textContent = 'Menyimpan...';
      google.script.run.withSuccessHandler(() => {
        msg.textContent = 'Tersimpan.'; f.reset();
        // Otomatis buat wallet untuk goal ini
        const walletPayload = { wallet: payload.goal, walletType: 'Other Asset', walletOwner: payload.goalOwner || '' };
        google.script.run.createWallet(walletPayload);
        bootstrap(); showToast('✅ Data diperbarui');
      }).withFailureHandler(err => { msg.textContent = err?.message || 'Gagal.'; })
        .createGoal(payload);
    };
  }

  // ======== START ========
  bootstrap();
})();
</script>
