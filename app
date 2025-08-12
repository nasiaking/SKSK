<script>
(() => {
  // ======== STATE ========
  let wallets = [];
  let categories = [];          // dari Category Setup
  let purposes = [];            // Expense Purposes (Account Setup)
  let txCache = [];

  // ======== ELEMENTS ========
  const setupView = document.getElementById('setupView');
  const appView   = document.getElementById('appView');
  const setupMsg  = document.getElementById('setupMsg');

  const btnSetupOpen = document.getElementById('btnSetupOpen'); // "Setup"
  const btnHome      = document.getElementById('btnHome');      // "Main"

  // Form transaksi
  const form    = document.getElementById('txForm');
  const dateInp = document.getElementById('date');
  const subSel  = document.getElementById('subcategory');
  const walSel  = document.getElementById('wallet');
  const amtInp  = document.getElementById('amount');
  const transferWrap = document.getElementById('transferWrap');
  const transferSel  = document.getElementById('transferTo');
  const expSel  = document.getElementById('expensePurpose'); // dropdown (Expense For)
  const noteInp = document.getElementById('note');
  const noteDL  = document.getElementById('noteOptions');
  const descInp = document.getElementById('description');

  // Riwayat & Laporan
  const txList = document.getElementById('txList');
  const search = document.getElementById('search');
  const budgetTbody = document.getElementById('budgetTbody');
  const goalsWrap   = document.getElementById('goalsWrap');

  // Master Setup
  const masterFormWrap = document.getElementById('masterFormWrap');
  const btnOpenAccount  = document.getElementById('btnOpenAccount');
  const btnOpenWallet   = document.getElementById('btnOpenWallet');
  const btnOpenCategory = document.getElementById('btnOpenCategory');
  const btnOpenGoals    = document.getElementById('btnOpenGoals');

  // ======== VIEW HELPERS ========
  function showSetup(){
    setupView.classList.remove('hidden');
    appView.classList.add('hidden');
    // bersihkan area master & reset highlight tombol
    masterFormWrap.innerHTML = '';
    [btnOpenAccount, btnOpenWallet, btnOpenCategory, btnOpenGoals]
      .forEach(b => b.classList.remove('bg-slate-800','text-white'));
  }
  function showApp(){ setupView.classList.add('hidden'); appView.classList.remove('hidden'); }

  btnSetupOpen.addEventListener('click', showSetup);
  btnHome.addEventListener('click', showApp);

  // ======== SETUP: Buat DB ========
  document.getElementById('btnCreateNew').addEventListener('click', () => {
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
    Promise.all([
      gs('getWallets'),
      gs('getCategories'),
      gs('getDistinctNotes', 25),
      gs('getExpensePurposes', 200),
    ]).then(([w, c, notes, purp]) => {
      wallets    = w || [];
      categories = c || [];
      purposes   = purp || [];

      // Subcategory: sembunyikan Transfer-In dari opsi manual
      const subOptions = (categories || []).map(x => x.Subcategory).filter(s => s && s !== 'Transfer-In');
      fillSelect(subSel, subOptions);

      // Wallet & Transfer To
      fillSelect(walSel, (wallets||[]).map(x => x.Wallet));
      fillSelect(transferSel, (wallets||[]).map(x => x.Wallet));

      // Notes datalist
      fillDatalist(noteDL, notes || []);

      // Expense For (selalu dropdown dari Account Setup)
      fillSelect(expSel, purposes);

      refreshTransferUI();
      loadTransactions();
      loadReports();

      // default date = hari ini (local)
      dateInp.valueAsNumber = Date.now() - (new Date()).getTimezoneOffset()*60000;

      showApp();
    }).catch(err => { console.log('Bootstrap gagal:', err); showSetup(); });
  }

  // ======== UTIL KONEKSI GAS & DOM ========
  function gs(fnName, arg) {
    return new Promise((resolve, reject) => {
      const call = google.script.run.withSuccessHandler(resolve).withFailureHandler(reject);
      (arg === undefined) ? call[fnName]() : call[fnName](arg);
    });
  }
  function fillSelect(sel, arr) {
    sel.innerHTML = '';
    (arr||[]).forEach(v => { const o = document.createElement('option'); o.value = v; o.textContent = v; sel.appendChild(o); });
  }
  function fillDatalist(dl, arr) {
    dl.innerHTML = '';
    (arr||[]).forEach(v => { const o = document.createElement('option'); o.value = v; dl.appendChild(o); });
  }

  // ======== TRANSFER UI ========
  function refreshTransferUI() {
    const isTransferOut = subSel.value === 'Transfer-Out';
    transferWrap.classList.toggle('hidden', !isTransferOut);
    if (isTransferOut) {
      const from = walSel.value;
      [...transferSel.options].forEach(o => { o.disabled = (o.value === from); });
      if (transferSel.value === from) transferSel.value = '';
    }
  }
  subSel.addEventListener('change', refreshTransferUI);
  walSel.addEventListener('change', refreshTransferUI);

  // ======== SUBMIT TRANSAKSI ========
  form.addEventListener('submit', (ev) => {
    ev.preventDefault();
    const isTO = (subSel.value === 'Transfer-Out');
    const payload = {
      date: dateInp.value,
      subcategory: subSel.value,
      wallet: walSel.value,
      amount: Number(amtInp.value || 0),
      transferTo: isTO ? transferSel.value : '',
      expensePurpose: expSel.value || '', // dari dropdown
      note: (noteInp.value || '').trim(),
      description: (descInp.value || '').trim(),
    };
    if (isTO && !payload.transferTo) { alert('Pilih dompet tujuan, Bung.'); return; }
    if (!payload.amount || payload.amount <= 0) { alert('Amount harus > 0.'); return; }

    disableForm(true);
    google.script.run.withSuccessHandler(() => {
      amtInp.value = ''; noteInp.value = ''; descInp.value = '';
      gs('getDistinctNotes', 25).then(list => fillDatalist(noteDL, list || []));
      loadTransactions(); loadReports();
      disableForm(false);
    }).withFailureHandler(err => { alert((err && err.message) || 'Gagal menyimpan.'); disableForm(false); })
      .addTransaction(payload);
  });

  function disableForm(dis){ form.querySelectorAll('input,select,button').forEach(el => el.disabled = dis); }

  // ======== RIWAYAT ========
  function loadTransactions() {
    gs('getTransactions')
      .then(list => { txCache = Array.isArray(list) ? list : []; renderTransactions(); })
      .catch(err => { console.log('Load tx failed:', err); txCache = []; renderTransactions(); });
  }

  function renderTransactions() {
    const q = (search.value || '').toLowerCase();
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
  search.addEventListener('input', renderTransactions);

  function safeDate(v){ try{ const d = new Date(v); return isFinite(d) ? d.toLocaleDateString() : ''; }catch(_){ return ''; } }
  function formatMoney(n){ return (new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0})).format(n||0); }
  function escapeHtml(s){ return String(s||'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m])); }

  // ======== LAPORAN ========
  function loadReports() {
    // Budget Summary: Category + Subcategory
    gs('getBudgetSummary').then(list => {
      budgetTbody.innerHTML = '';
      (list || []).forEach(r => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td class="p-2">${escapeHtml(r.category || '')}</td>
          <td class="p-2">${escapeHtml(r.subcategory || '')}</td>
          <td class="p-2 text-right">${formatMoney(r.spent || 0)}</td>
          <td class="p-2 text-right">${formatMoney(r.remaining || 0)}</td>
        `;
        budgetTbody.appendChild(tr);
      });
    }).catch(() => { budgetTbody.innerHTML = ''; });

    // Goals Progress
    gs('getGoalsWithProgress').then(list => {
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
    }).catch(() => { goalsWrap.innerHTML = ''; });
  }

  // ======== MASTER VIEW SWITCHER (TAB) ========
  function renderIntoMaster(html) {
    masterFormWrap.innerHTML = '';                         // kosongkan area form
    const wrapper = document.createElement('div');
    wrapper.innerHTML = html.trim();
    masterFormWrap.appendChild(wrapper.firstElementChild); // taruh satu form saja
  }
// ======== MASTER TAB STATE ========
const MASTER_BTNS = [btnOpenAccount, btnOpenWallet, btnOpenCategory, btnOpenGoals];

function setActiveMaster(btn){
  MASTER_BTNS.forEach(b => {
    b.classList.remove(
      'font-semibold','underline','decoration-white','decoration-[3px]','underline-offset-8'
    );
    b.classList.add('text-white'); // pastikan semua standby font putih
    b.setAttribute('aria-selected','false');
  });

  btn.classList.add(
    'font-semibold','underline','decoration-white','decoration-[3px]','underline-offset-8','text-white'
  );
  btn.setAttribute('aria-selected','true');
}


  function openMaster(section){
    switch(section){
      case 'account':  renderAccountForm();  setActiveMaster(btnOpenAccount);  break;
      case 'wallet':   renderWalletForm();   setActiveMaster(btnOpenWallet);   break;
      case 'category': renderCategoryForm(); setActiveMaster(btnOpenCategory); break;
      case 'goals':    renderGoalsForm();    setActiveMaster(btnOpenGoals);    break;
    }
  }

  btnOpenAccount .addEventListener('click', () => openMaster('account'));
  btnOpenWallet  .addEventListener('click', () => openMaster('wallet'));
  btnOpenCategory.addEventListener('click', () => openMaster('category'));
  btnOpenGoals   .addEventListener('click', () => openMaster('goals'));

  // ——— Account (Expense Purpose) — tambah baru
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
        // refresh master data
        gs('getExpensePurposes', 200).then(list => {
          purposes = list || [];
          fillSelect(expSel, purposes); // form transaksi
          // refresh owner dropdown di Wallet & Goals form bila aktif
          const walletOwnerSel = document.getElementById('walletOwnerSel');
          if (walletOwnerSel) fillSelect(walletOwnerSel, purposes);
          const goalOwnerSel = document.getElementById('goalOwnerSel');
          if (goalOwnerSel) fillSelect(goalOwnerSel, purposes);
        });
      }).withFailureHandler(err => { msg.textContent = err?.message || 'Gagal.'; })
        .createAccountPurpose(payload);
    };
  }

  // ——— Wallet — tambah baru (Owner dari Expense Purpose)
  function renderWalletForm() {
    renderIntoMaster(`
      <div id="walletForm" class="border rounded p-3">
        <h4 class="font-medium mb-2">Tambah Wallet</h4>
        <form id="fWallet" class="grid grid-cols-3 gap-3">
          <label class="col-span-1">Wallet
            <input name="wallet" class="mt-1 w-full border rounded p-2" required />
          </label>
          
          <label class="col-span-1">Wallet Type
            <select id="walletTypeSel" name="walletType" class="mt-1 w-full border rounded p-2">
              <option>Cash &amp; Bank</option>
              <option>Liabilities</option>
              <option>Saving</option>
              <option>Other Asset</option>
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
    // isi owner dari Expense Purpose
    const ownerSel = document.getElementById('walletOwnerSel');
    fillSelect(ownerSel, purposes);

    const f = document.getElementById('fWallet'), msg = document.getElementById('msgWallet');
    f.onsubmit = (e) => {
      e.preventDefault();
      const payload = Object.fromEntries(new FormData(f).entries());
      msg.textContent = 'Menyimpan...';
      google.script.run.withSuccessHandler(() => {
        msg.textContent = 'Tersimpan.'; f.reset();
        // refresh dropdown wallet & transferTo di form transaksi
        gs('getWallets').then(w => {
          wallets = w || [];
          fillSelect(walSel, wallets.map(x=>x.Wallet));
          fillSelect(transferSel, wallets.map(x=>x.Wallet));
        });
      }).withFailureHandler(err => { msg.textContent = err?.message || 'Gagal.'; })
        .createWallet(payload);
    };
  }

  // ——— Category — pilih kategori yang sudah ada atau Tambah Baru…
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
              <option>Expense</option>
              <option>Income</option>
              <option>Transfer</option>
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

    // isi kategori unik + "Tambah Baru…"
    const uniqueCats = Array.from(new Set((categories||[]).map(x => x.Category).filter(Boolean))).sort();
    catSel.innerHTML = '';
    [...uniqueCats, '— Tambah Baru… —'].forEach(v => {
      const o = document.createElement('option'); o.value = v; o.textContent = v; catSel.appendChild(o);
    });
    const NEW_VAL = '— Tambah Baru… —';
    if (uniqueCats.length === 0) catSel.value = NEW_VAL;

    catSel.addEventListener('change', () => {
      const isNew = (catSel.value === NEW_VAL);
      newCatWrap.classList.toggle('hidden', !isNew);
      if (isNew) newCatInp.focus();
    });
    catSel.dispatchEvent(new Event('change'));

    const f = document.getElementById('fCategory'), msg = document.getElementById('msgCategory');
    f.onsubmit = (e) => {
      e.preventDefault();
      const isNew = (catSel.value === NEW_VAL);
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
        // refresh master categories + subcategory dropdown transaksi
        gs('getCategories').then(c => {
          categories = c || [];
          const subs = categories.map(x=>x.Subcategory).filter(s => s && s !== 'Transfer-In');
          fillSelect(subSel, subs);
        });
        // refresh isi dropdown category di form ini
        const latestUnique = Array.from(new Set((categories||[]).map(x => x.Category).filter(Boolean))).sort();
        catSel.innerHTML = '';
        [...latestUnique, NEW_VAL].forEach(v => {
          const o = document.createElement('option'); o.value = v; o.textContent = v; catSel.appendChild(o);
        });
        catSel.value = latestUnique[0] || NEW_VAL;
        catSel.dispatchEvent(new Event('change'));
      }).withFailureHandler(err => { msg.textContent = err?.message || 'Gagal.'; })
        .createCategory(payload);
    };
  }

  // ——— Goals — Owner dari Expense Purpose
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
        loadReports();
      }).withFailureHandler(err => { msg.textContent = err?.message || 'Gagal.'; })
        .createGoal(payload);
    };
  }

  // ======== START ========
  bootstrap();
})();
</script>
