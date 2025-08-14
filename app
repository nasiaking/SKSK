<script>
(() => {
  // ======== STATE ========
  let wallets = [];
  let categories = [];
  let purposes = [];
  let txCache = [];
  let walletBalances = [];
  let _budgetCache = [];
  let _goalsCache = [];

  let historyPage = 1;
  let historyHasMore = true;
  let isHistoryLoading = false;
  let isReportLoaded = false;
  let isHistoryLoaded = false;
  let searchDebounceTimer;


  // ======== ELEMENTS ========
  const setupView      = document.getElementById('setupView');
  const dashboardView  = document.getElementById('dashboardView');
  const historyView    = document.getElementById('historyView');
  const reportView     = document.getElementById('reportView');
  const loadingIndicator = document.getElementById('loadingIndicator');

  const btnTabDashboard = document.getElementById('btnTabDashboard');
  const btnTabHistory   = document.getElementById('btnTabHistory');
  const btnTabReport    = document.getElementById('btnTabReport');
  const btnSetupOpen    = document.getElementById('btnSetupOpen');

  const setupMsg  = document.getElementById('setupMsg');

  // Quick Add form
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
  const btnLoadMore = document.getElementById('btnLoadMore');
  const budgetTbody = document.getElementById('budgetTbody');
  const goalsWrap   = document.getElementById('goalsWrap');

  // Dashboard widgets
  const walletBalancesWrap = document.getElementById('walletBalancesWrap');
  const budgetOverviewWrap = document.getElementById('budgetOverviewWrap');
  const btnRefreshHeader   = document.getElementById('btnRefreshHeader');

  // --- GEMINI FEATURE ELEMENTS ---
  const btnAnalyzeReport = document.getElementById('btnAnalyzeReport');
  const reportAnalysisResult = document.getElementById('reportAnalysisResult');


  // ======== Toast ========
  const toast = document.createElement('div');
  toast.id = 'toastNotif';
  toast.style.cssText = `
    position: fixed; bottom: 20px; right: 20px; background:#10b981; color:white;
    padding:10px 15px; border-radius:8px; font-size:14px; display:none; z-index:9999;
  `;
  document.body.appendChild(toast);
  function showToast(msg, isError = false){
    toast.textContent = msg;
    toast.style.backgroundColor = isError ? '#dc2626' : '#10b981';
    toast.style.display='block';
    setTimeout(()=>toast.style.display='none', 4000);
  }

  // ======== NAV & LAZY LOADING ========
  function showOnly(viewEl){
    [setupView, dashboardView, historyView, reportView].forEach(v => v && v.classList.add('hidden'));
    viewEl && viewEl.classList.remove('hidden');
    hideLoading();
  }

  btnTabDashboard?.addEventListener('click', () => { showOnly(dashboardView); });
  btnTabHistory?.addEventListener('click', () => {
    showOnly(historyView);
    if (!isHistoryLoaded) {
        fetchHistory();
        isHistoryLoaded = true;
    }
  });
  btnTabReport?.addEventListener('click', () => {
    showOnly(reportView);
    if (!isReportLoaded) {
        showLoading('Loading reports...');
        gs('getReportData').then(data => {
            _budgetCache = data.budgetSummary || [];
            _goalsCache = data.goalsProgress || [];
            renderBudgetSummary(_budgetCache);
            renderGoalsProgress(_goalsCache);
            isReportLoaded = true;
        }).catch(handleError);
    }
  });
  btnSetupOpen?.addEventListener('click', () => { showOnly(setupView); });

  btnRefreshHeader?.addEventListener('click', () => {
    showLoading('Updating data...');
    isHistoryLoaded = false;
    isReportLoaded = false;
    txCache = [];
    historyPage = 1;
    historyHasMore = true;
    bootstrap();
    showToast('✅ Data updated');
  });

  function showLoading(message = 'Loading...') {
    if (!loadingIndicator) return;
    loadingIndicator.textContent = message;
    loadingIndicator.classList.remove('hidden');
  }
  function hideLoading() {
    loadingIndicator?.classList.add('hidden');
  }
  function handleError(err) {
    const message = (err && err.message) || 'An error occurred.';
    console.error('Error:', message);
    showToast(message, true);
    hideLoading();
  }


  // ======== SETUP: Buat DB ========
  document.getElementById('btnCreateNew')?.addEventListener('click', () => {
    setupMsg.textContent = 'Creating database in your Drive...';
    gs('createNewDb').then(() => {
      setupMsg.textContent = 'Database created & connected. Loading app...';
      bootstrap();
    }).catch(err => {
      setupMsg.textContent = (err && err.message) || 'Failed to create database.';
    });
  });

  // ======== BOOTSTRAP (INITIAL LOAD) ========
  function bootstrap() {
    showLoading('Loading initial data...');
    gs('getDashboardData').then(data => {
      wallets        = data.wallets || [];
      categories     = data.categories || [];
      purposes       = data.purposes || [];
      _budgetCache   = data.budgetSummary || [];
      walletBalances = data.walletBalances || [];

      const subOptions = (categories||[]).map(x => x.Subcategory).filter(s => s && s !== 'Transfer-In');
      fillSelect(subSel, subOptions);
      fillSelect(walSel, (wallets||[]).map(x => x.Wallet));
      fillSelect(transferSel, (wallets||[]).map(x => x.Wallet));
      fillDatalist(noteDL, data.notes || []);
      fillSelect(expSel, purposes);

      renderDashboard();
      dateInp && (dateInp.valueAsNumber = Date.now() - (new Date()).getTimezoneOffset()*60000);
      showOnly(dashboardView);
    }).catch(handleError);
  }

  // ======== UTIL KONEKSI GAS & DOM ========
  function gs(fnName, arg) {
    return new Promise((resolve, reject) => {
      google.script.run
        .withSuccessHandler(res => { hideLoading(); resolve(res); })
        .withFailureHandler(err => { hideLoading(); reject(err); })
        [fnName](arg);
    });
  }
  function fillSelect(sel, arr) {
    if (!sel) return;
    sel.innerHTML = '<option value="">-- Select --</option>';
    (arr||[]).forEach(v => { const o = document.createElement('option'); o.value = v; o.textContent = v; sel.appendChild(o); });
  }
  function fillDatalist(dl, arr) {
    if (!dl) return;
    dl.innerHTML = '';
    (arr||[]).forEach(v => { const o = document.createElement('option'); o.value = v; dl.appendChild(o); });
  }
  function formatMoney(n){ return (new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0})).format(n||0); }
  function safeDate(v){ try{ const d=new Date(v); return isFinite(d)? d.toLocaleDateString('en-CA'):'';}catch(_){return '';} }
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

  // ======== SUBMIT TRANSAKSI ========
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
    if (!payload.subcategory || !payload.wallet) { showToast('Subcategory and Wallet are required.', true); return; }
    if (isTO && !payload.transferTo) { showToast('Please select a destination wallet.', true); return; }
    if (!payload.amount || payload.amount <= 0) { showToast('Amount must be greater than 0.', true); return; }

    disableForm(true);
    showLoading('Saving transaction...');

    gs('addTransaction', payload).then(result => {
        amtInp.value = ''; noteInp.value = ''; descInp.value = '';
        showToast('✅ Transaction saved');
        gs('getDashboardData').then(data => {
            walletBalances = data.walletBalances || [];
            _budgetCache = data.budgetSummary || [];
            renderDashboardCards();
            renderBudgetOverview();
        });
        if(isHistoryLoaded) {
            txCache.unshift(result.transaction);
            renderTransactions();
        }
    }).catch(handleError).finally(() => {
        disableForm(false);
    });
  });
  function disableForm(dis){ form?.querySelectorAll('input,select,button').forEach(el => el.disabled = dis); }

  // ======== HISTORY & PAGINATION ========
  function fetchHistory() {
      if (isHistoryLoading || !historyHasMore) return;
      isHistoryLoading = true;
      showLoading('Loading history...');
      btnLoadMore?.classList.add('hidden');

      gs('getHistoryTransactions', { page: historyPage, limit: 50 }).then(result => {
          if (result && result.transactions) {
            txCache.push(...result.transactions);
            historyHasMore = result.hasMore;
            historyPage++;
            renderTransactions();
            if (historyHasMore) {
                btnLoadMore?.classList.remove('hidden');
            }
          } else {
            historyHasMore = false;
            btnLoadMore?.classList.add('hidden');
            if (txCache.length === 0) {
                renderTransactions();
            }
          }
      }).catch(handleError).finally(() => {
          isHistoryLoading = false;
      });
  }
  btnLoadMore?.addEventListener('click', fetchHistory);

  function renderTransactions() {
    if (!txList) return;
    const q = (search?.value || '').toLowerCase();
    txList.innerHTML = '';
    const rows = txCache.filter(tx => {
      if (!q) return true;
      const line = [
        tx.Wallet, tx.Subcategory, tx.Category,
        safeDate(tx.Date), String(tx.Amount),
        tx.Note || '', tx.Description || ''
      ].join(' ').toLowerCase();
      return line.includes(q);
    });

    if (!rows.length) {
      txList.innerHTML = `<div class="text-sm text-slate-500 p-4 text-center">No transactions yet.</div>`;
      return;
    }

    rows.forEach(tx => {
      const el = document.createElement('div');
      el.className = 'border-b p-2 text-sm flex items-center justify-between';
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

  search?.addEventListener('input', () => {
      clearTimeout(searchDebounceTimer);
      searchDebounceTimer = setTimeout(() => {
          renderTransactions();
      }, 300);
  });


  // ======== REPORTS & GEMINI FEATURES ========
  btnAnalyzeReport?.addEventListener('click', () => {
    const btn = btnAnalyzeReport;
    btn.disabled = true;
    reportAnalysisResult.innerHTML = '<p class="text-slate-500">Analyzing data with AI...</p>';

    gs('getFinancialAnalysis', _budgetCache).then(htmlResult => {
      reportAnalysisResult.innerHTML = htmlResult;
    }).catch(err => {
      reportAnalysisResult.innerHTML = `<p class="text-rose-600">Analysis failed: ${err.message}</p>`;
    }).finally(() => {
      btn.disabled = false;
    });
  });

  function renderBudgetSummary(list) {
    if (!budgetTbody) return;
    budgetTbody.innerHTML = '';
    const rows = (list || []).filter(r => String(r.category||'').toLowerCase() !== 'transfer');
    if (!rows.length) {
        budgetTbody.innerHTML = `<tr><td colspan="4" class="text-center p-4 text-slate-500">No budget data.</td></tr>`;
        return;
    }
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
    if (!list || !list.length) {
        goalsWrap.innerHTML = `<div class="text-sm text-slate-500 p-4 text-center">No goals yet.</div>`;
        return;
    }
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
    renderBudgetOverview();
    refreshTransferUI();
  }
  function renderDashboardCards(){
    if (!walletBalancesWrap) return;
    const h2 = walletBalancesWrap.closest('section').querySelector('h2');
    let inlineEl = h2?.querySelector('#netWorthInline');
    if (h2 && !inlineEl) {
        inlineEl = document.createElement('span');
        inlineEl.id = 'netWorthInline';
        inlineEl.className = 'ml-2';
        h2.appendChild(inlineEl);
    }
    walletBalancesWrap.className = 'space-y-4 mt-2';
    const ORDER = ['Cash & Bank','Savings/Investments','Other Asset','Liabilities'];
    const groups = { 'Cash & Bank':[], 'Savings/Investments':[], 'Other Asset':[], 'Liabilities':[] };
    (walletBalances||[]).forEach(w => {
      const t = ORDER.includes(w.type) ? w.type : 'Other Asset';
      groups[t].push(w);
    });
    let net = 0;
    Object.values(groups).forEach(arr => arr.forEach(w => {
        let v = Number(w.balance || 0);
        if (w.type === 'Liabilities' && v > 0) v = -v;
        net += v;
    }));
    if (inlineEl){
      inlineEl.textContent = formatMoney(net);
      inlineEl.classList.remove('text-rose-700','text-emerald-700');
      inlineEl.classList.add(net < 0 ? 'text-rose-700' : 'text-emerald-700');
    }
    walletBalancesWrap.innerHTML = '';
    ORDER.forEach(type => {
      if (!groups[type] || !groups[type].length) return;
      const arr = groups[type].slice().sort((a,b)=> a.wallet.localeCompare(b.wallet));
      let subtotal = 0;
      arr.forEach(w => {
        let v = Number(w.balance || 0);
        if (type === 'Liabilities' && v > 0) v = -v;
        subtotal += v;
      });
      const subCls = subtotal < 0 ? 'text-rose-600' : (subtotal > 0 ? 'text-emerald-600' : 'text-slate-500');
      const g = document.createElement('div');
      const hdr = document.createElement('button');
      hdr.type = 'button';
      hdr.className = 'w-full flex items-center justify-between text-sm font-medium text-slate-700';
      hdr.innerHTML = `<span class="inline-flex items-center gap-2"><span class="inline-block rotate-0 transition-transform" aria-hidden="true">▾</span>${escapeHtml(type)}</span><span class="${subCls}">${formatMoney(subtotal)}</span>`;
      g.appendChild(hdr);
      const body = document.createElement('div');
      body.className = 'grid grid-cols-1 md:grid-cols-2 gap-3 mt-2';
      arr.forEach(w => {
          const val = Number(w.balance || 0);
          const cls = (val < 0) ? 'text-rose-600' : (val > 0) ? 'text-emerald-600' : 'text-slate-500';
          const card = document.createElement('div');
          card.className = 'border rounded p-3 flex items-center justify-between';
          card.innerHTML = `<div class="font-medium">${escapeHtml(w.wallet)}</div><div class="${cls} font-semibold">${formatMoney(val)}</div>`;
          body.appendChild(card);
        });
      g.appendChild(body);
      hdr.addEventListener('click', () => {
        const caret = hdr.querySelector('span[aria-hidden="true"]');
        const isOpen = !body.classList.contains('hidden');
        body.classList.toggle('hidden', isOpen);
        caret.style.transform = isOpen ? 'rotate(-90deg)' : 'rotate(0deg)';
      });
      walletBalancesWrap.appendChild(g);
    });
  }
  function renderBudgetOverview(){
    if (!budgetOverviewWrap) return;
    budgetOverviewWrap.innerHTML = '';
    const rows = (_budgetCache || []).filter(r => r.budget > 0 && String(r.category||'').toLowerCase() !== 'transfer');
    if (!rows.length){
      budgetOverviewWrap.innerHTML = `<div class="text-sm text-slate-500">No budget data for this month.</div>`;
      return;
    }
    rows.sort((a,b)=> (a.remaining||0) - (b.remaining||0)).slice(0, 5).forEach(r => {
      const total = Number(r.budget||0);
      const spent = Number(r.spent||0) * -1;
      const pct = total > 0 ? Math.min(1, spent/total) : 0;
      const item = document.createElement('div');
      item.className = 'mb-2';
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
  const masterFormWrap = document.getElementById('masterFormWrap');
  const btnOpenAccount  = document.getElementById('btnOpenAccount');
  const btnOpenWallet   = document.getElementById('btnOpenWallet');
  const btnOpenCategory = document.getElementById('btnOpenCategory');
  const btnOpenGoals    = document.getElementById('btnOpenGoals');

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

  function renderAccountForm() {
    renderIntoMaster(`
      <div id="accountForm" class="border rounded p-3">
        <h4 class="font-medium mb-2">Add Expense Purpose</h4>
        <form id="fAccount" class="grid grid-cols-2 gap-3">
          <label class="col-span-2">Expense Purpose
            <input name="expensePurpose" class="mt-1 w-full border rounded p-2" required />
          </label>
          <div class="col-span-2 flex justify-end">
            <button class="px-3 py-2 bg-emerald-600 text-white rounded">Save</button>
          </div>
        </form>
        <p id="msgAccount" class="text-sm text-slate-600 mt-2"></p>
      </div>
    `);
    const f = document.getElementById('fAccount'), msg = document.getElementById('msgAccount');
    f.onsubmit = (e) => {
      e.preventDefault();
      const payload = Object.fromEntries(new FormData(f).entries());
      msg.textContent = 'Saving...';
      gs('createAccountPurpose', payload).then(() => {
        msg.textContent = 'Saved.'; f.reset();
        gs('getDashboardData').then(d => { purposes = d.purposes; fillSelect(expSel, purposes); });
        showToast('✅ Data updated');
      }).catch(err => { msg.textContent = err?.message || 'Failed.'; });
    };
  }
  function renderWalletForm() {
    renderIntoMaster(`
      <div id="walletForm" class="border rounded p-3">
        <h4 class="font-medium mb-2">Add Wallet</h4>
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
            <button class="px-3 py-2 bg-emerald-600 text-white rounded">Save</button>
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
      msg.textContent = 'Saving...';
      gs('createWallet', payload).then(() => {
        msg.textContent = 'Saved.'; f.reset();
        gs('getDashboardData').then(d => {
            wallets = d.wallets;
            fillSelect(walSel, wallets.map(x=>x.Wallet));
            fillSelect(transferSel, wallets.map(x=>x.Wallet));
        });
        showToast('✅ Data updated');
      }).catch(err => { msg.textContent = err?.message || 'Failed.'; });
    };
  }
  function renderCategoryForm() {
    renderIntoMaster(`
      <div id="categoryForm" class="border rounded p-3">
        <h4 class="font-medium mb-2">Add Category/Subcategory</h4>
        <form id="fCategory" class="grid grid-cols-3 gap-3">
          <label class="col-span-1">Category
            <select id="categorySel" name="categorySel" class="mt-1 w-full border rounded p-2"></select>
          </label>
          <label id="newCatWrap" class="col-span-1 hidden">Category (New)
            <input id="newCategory" class="mt-1 w-full border rounded p-2" placeholder="New Category Name" />
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
            <button class="px-3 py-2 bg-emerald-600 text-white rounded">Save</button>
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
      const NEW_VAL = '— Add New… —';
      fillSelect(catSel, [...uniqueCats, NEW_VAL]);
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
      const isNew = (catSel.value === '— Add New… —');
      const category = isNew ? (newCatInp.value || '').trim() : catSel.value;
      if (!category) { msg.textContent = 'New category name is required.'; return; }
      const fd = new FormData(f);
      const payload = {
        category,
        subcategory: (fd.get('subcategory') || '').trim(),
        transactionType: fd.get('transactionType') || 'Expense',
      };
      if (!payload.subcategory) { msg.textContent = 'Subcategory is required.'; return; }
      msg.textContent = 'Saving...';
      gs('createCategory', payload).then(() => {
        msg.textContent = 'Saved.'; f.reset(); newCatInp.value = '';
        gs('getDashboardData').then(d => {
            categories = d.categories;
            const subOptions = categories.map(x => x.Subcategory).filter(s => s && s !== 'Transfer-In');
            fillSelect(subSel, subOptions);
        });
        showToast('✅ Data updated');
      }).catch(err => { msg.textContent = err?.message || 'Failed.'; });
    };
  }
  function renderGoalsForm() {
    renderIntoMaster(`
      <div id="goalsForm" class="border rounded p-3">
        <h4 class="font-medium mb-2">Add Goal</h4>
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
          <div class="col-span-3 flex justify-end items-center gap-3">
            <button id="btnPlanGoal" type="button" class="px-3 py-2 text-sm bg-sky-600 text-white rounded hover:bg-sky-700 transition flex items-center disabled:opacity-50">
              <span class="mr-2">✨</span> Create Plan
            </button>
            <button class="px-3 py-2 bg-emerald-600 text-white rounded">Save</button>
          </div>
        </form>
        <div id="goalPlanResult" class="mt-4 text-sm"></div>
        <p id="msgGoal" class="text-sm text-slate-600 mt-2"></p>
      </div>
    `);
    const ownerSel = document.getElementById('goalOwnerSel');
    fillSelect(ownerSel, purposes);
    const f = document.getElementById('fGoal'), msg = document.getElementById('msgGoal');
    
    const btnPlanGoal = document.getElementById('btnPlanGoal');
    const goalPlanResult = document.getElementById('goalPlanResult');
    btnPlanGoal.addEventListener('click', () => {
      const goalName = f.elements.goal.value;
      const nominalNeeded = f.elements.nominalNeeded.value;
      if (!goalName || !nominalNeeded) {
        showToast('Please fill in Goal name and Nominal Needed first.', true);
        return;
      }
      btnPlanGoal.disabled = true;
      goalPlanResult.innerHTML = '<p class="text-slate-500">Creating plan with AI...</p>';
      gs('getGoalSavingsPlan', { goalName, nominalNeeded }).then(htmlResult => {
        goalPlanResult.innerHTML = `<div class="p-3 bg-sky-50 rounded-lg border border-sky-200">${htmlResult}</div>`;
      }).catch(err => {
        goalPlanResult.innerHTML = `<p class="text-rose-600">Failed to create plan: ${err.message}</p>`;
      }).finally(() => {
        btnPlanGoal.disabled = false;
      });
    });

    f.onsubmit = (e) => {
      e.preventDefault();
      const payload = Object.fromEntries(new FormData(f).entries());
      msg.textContent = 'Saving...';
      gs('createGoal', payload).then(() => {
        msg.textContent = 'Saved.'; f.reset(); goalPlanResult.innerHTML = '';
        const walletPayload = { wallet: payload.goal, walletType: 'Other Asset', walletOwner: payload.goalOwner || '' };
        gs('createWallet', walletPayload);
        showToast('✅ New Goal & Wallet saved');
      }).catch(err => { msg.textContent = err?.message || 'Failed.'; });
    };
  }

  // ======== START ========
  bootstrap();
})();
</script>
