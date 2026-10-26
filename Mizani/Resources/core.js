/* Shared by the native iOS app (JavaScriptCore) and Node tests. No network. */
(function (root) {
  'use strict';
  const MAX = 9000000000000;
  const kinds = ['outgoing', 'incoming', 'purchase', 'refund', 'deposit', 'expense', 'income'];
  const outgoing = k => ['outgoing', 'purchase', 'expense'].includes(k);
  const iso = value => { const d = new Date(value); if (!Number.isFinite(d.getTime())) throw new Error('تاريخ غير صالح.'); return d.toISOString(); };
  function normalized(v) {
    return String(v || '').normalize('NFKC').replace(/[\u0660-\u0669]/g, c => String(c.charCodeAt(0) - 0x660))
      .replace(/[\u06f0-\u06f9]/g, c => String(c.charCodeAt(0) - 0x6f0)).replace(/\u066b/g, '.').replace(/\u066c/g, ',')
      .replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, '').replace(/\s+/g, ' ').trim();
  }
  function units(n, zero) { if (!Number.isSafeInteger(n) || n > MAX || n < (zero ? 0 : 1)) throw new Error('قيمة المبلغ غير صالحة.'); return n; }
  function money(v, zero) {
    const raw = normalized(v);
    if (!/^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,3})?$/.test(raw)) throw new Error('أدخل مبلغاً صحيحاً بحد أقصى ثلاث خانات عشرية.');
    const p = raw.replace(/,/g, '').split('.'); return units(Number(p[0]) * 1000 + Number((p[1] || '').padEnd(3, '0')), zero);
  }
  const format = n => (n < 0 ? '-' : '') + Math.floor(Math.abs(n) / 1000).toLocaleString('en-US') + '.' + String(Math.abs(n) % 1000).padStart(3, '0');
  function digest(text) {
    let a = 2166136261, b = 5381;
    for (let i = 0; i < text.length; i++) { a = Math.imul(a ^ text.charCodeAt(i), 16777619); b = Math.imul(b, 33) ^ text.charCodeAt(i); }
    return (a >>> 0).toString(16) + (b >>> 0).toString(16) + text.length.toString(16);
  }
  const capture = (t, re) => { const m = t.match(re); return m ? m[1].trim() : null; };
  function dateInMessage(t) {
    const m = t.match(/\b(\d{4}[\/-]\d{1,2}[\/-]\d{1,2}|\d{1,2}[\/-]\d{1,2}[\/-]\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\b/);
    if (!m) return null;
    const p = m[1].split(/[\/-]/).map(Number), [y, mo, d] = p[0] > 999 ? p : [p[2], p[1], p[0]];
    const h = Number(m[2]), min = Number(m[3]), s = Number(m[4] || 0), date = new Date(Date.UTC(y, mo - 1, d, h, min, s));
    if (y < 2000 || y > 2100 || date.getUTCFullYear() !== y || date.getUTCMonth() !== mo - 1 || date.getUTCDate() !== d || h > 23 || min > 59 || s > 59) throw new Error('تاريخ العملية في الرسالة غير صالح.');
    return new Date(date.getTime() - 4 * 3600000).toISOString();
  }
  const amountPart = '((?:\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.\\d{1,3})?)(?!\\d|[.,]\\d)';
  function parseOne(raw, receivedAt) {
    const text = normalized(raw);
    if (!text || text.length > 12000) throw new Error('نص الرسالة فارغ أو طويل جداً.');
    const starts = text.match(/Dear Customer|عزيزي الزبون|تم خصم|تم إيداع/gi) || [];
    if (starts.length > 1) throw new Error('افصل كل رسالة عن التالية بسطر فارغ.');
    let kind;
    if (/reversed and credited|تم (?:عكس|إرجاع|ارجاع)|استرداد مبلغ/i.test(text)) kind = 'refund';
    else if (/you have sent|لقد أرسلت|لقد ارسلت/i.test(text)) kind = 'outgoing';
    else if (/لقد استلمت|you have received/i.test(text)) kind = 'incoming';
    else if (/تم إيداع|تم ايداع|cash deposit/i.test(text)) kind = 'deposit';
    else if (/تم خصم/i.test(text) && /بطاقة|card/i.test(text)) kind = 'purchase';
    else throw new Error('لم أتعرف على نوع الرسالة. راجعها أو أضف العملية يدوياً.');
    const prefixes = {
      outgoing: '(?:you have sent|لقد أرسلت|لقد ارسلت)\\s+(?:OMR\\s*)?',
      incoming: '(?:لقد استلمت|you have received)\\s+(?:OMR\\s*)?',
      deposit: '(?:تم إيداع|تم ايداع|cash deposit(?: of)?)\\s+(?:OMR\\s*)?',
      purchase: 'تم خصم\\s+(?:OMR\\s*)?',
      refund: '(?:card for\\s+OMR|(?:عكس|إرجاع|ارجاع|استرداد)\\s+(?:مبلغ\\s+)?(?:OMR\\s*)?)\\s*'
    };
    const amountRaw = capture(text, new RegExp(prefixes[kind] + amountPart, 'i'));
    if (!amountRaw || !/\bOMR\b/i.test(text)) throw new Error('لم أستطع تحديد مبلغ العملية بالريال العماني.');
    const amount = money(amountRaw), account = capture(text, /(?:a\/c|credited to|حسابك(?: رقم)?)\s*([\dXx*]{6,})/i);
    if (!account) throw new Error('لم أستطع تحديد الحساب البنكي.');
    const balanceRaw = capture(text, new RegExp('(?:Avl Bal|New Available Balance is|رصيدك الحالي هو)\\s*(?:OMR\\s*)?' + amountPart, 'i'));
    if (balanceRaw === null && /Avl Bal|New Available Balance is|رصيدك الحالي هو/i.test(text)) throw new Error('صيغة الرصيد غير واضحة. راجع الرسالة.');
    const bankBalance = balanceRaw === null ? null : money(balanceRaw, true);
    const transactionID = capture(text, /(?:Txn Id|رقم المعاملة)\s*[:.]?\s*([A-Z0-9]{6,})/i);
    let party = null;
    if (kind === 'outgoing') party = capture(text, /\bto\s+(.+?)\s+from your a\/c/i);
    if (kind === 'incoming') party = capture(text, /(?:من|\bfrom)\s+(.+?)\s+(?:في حسابك|(?:to|in) your a\/c)/i);
    if (kind === 'purchase') party = capture(text, /(?:المباشر|card)\s+(?:في|at)\s+(.+?)\s+بتاريخ/i);
    if (kind === 'deposit') party = 'جهاز الإيداع النقدي';
    if (kind === 'refund') party = 'استرجاع عملية بطاقة';
    const occurredAt = dateInMessage(text), received = iso(receivedAt || new Date());
    const semantic = [account.toUpperCase(), kind, amount, occurredAt || '', bankBalance, normalized(party).toUpperCase()].join('|');
    return { id: transactionID ? 'bank-' + account.toUpperCase() + '-' + transactionID.toUpperCase() : 'sms-' + digest(semantic),
      fingerprint: digest(semantic), transactionID, account: account.toUpperCase(), kind, amount, bankBalance, party: party || 'عملية بنكية',
      occurredAt: occurredAt || received, dateEstimated: occurredAt === null, receivedAt: received,
      category: kind === 'purchase' && /ROP|TRAFFIC/i.test(party || '') ? 'خدمات حكومية' : kind === 'purchase' ? 'مشتريات' : kind === 'refund' ? 'استرجاع' : kind === 'deposit' ? 'إيداع نقدي' : 'تحويلات',
      envelopeID: null, excluded: false, source: 'sms' };
  }
  function parse(text, receivedAt) {
    const chunks = String(text || '').trim().split(/\r?\n\s*\r?\n/).filter(s => s.trim());
    if (!chunks.length) throw new Error('أدخل نص الرسالة أولاً.');
    if (chunks.length > 300) throw new Error('استورد 300 رسالة أو أقل في كل مرة.');
    const transactions = [], errors = [];
    chunks.forEach((s, i) => { try { transactions.push(parseOne(s, receivedAt)); } catch (e) { errors.push({ index: i + 1, message: e.message }); } });
    return { transactions, errors };
  }
  function emptyState() { return { version: 1, transactions: [], envelopes: [], rules: [], anchors: [], settings: { lowBalance: 10000, monthlyLimit: 0, warningPercent: 80 } }; }
  const signed = t => outgoing(t.kind) ? -t.amount : t.amount;
  const at = t => Date.parse(t.occurredAt);
  function balance(s, account) {
    const anchors = s.transactions.filter(t => t.account === account && !t.dateEstimated && t.bankBalance != null)
      .map(t => ({ amount: t.bankBalance, date: t.occurredAt, origin: 'sms' }))
      .concat(s.anchors.filter(a => a.account === account).map(a => ({ amount: a.amount, date: a.date, origin: 'manual' })))
      .sort((a, b) => Date.parse(b.date) - Date.parse(a.date));
    if (!anchors.length) return { amount: null, date: null, origin: null };
    const a = anchors[0];
    return { amount: a.amount + s.transactions.filter(t => t.account === account && !t.dateEstimated && at(t) > Date.parse(a.date)).reduce((sum, t) => sum + signed(t), 0), date: a.date, origin: a.origin };
  }
  function envelopeView(s, e) {
    const spent = Math.max(0, s.transactions.filter(t => t.envelopeID === e.id && !t.excluded).reduce((sum, t) => sum + (outgoing(t.kind) ? t.amount : t.kind === 'refund' ? -t.amount : 0), 0));
    return Object.assign({}, e, { spent, remaining: Math.max(0, e.allocated - spent), overspent: Math.max(0, spent - e.allocated), percent: e.allocated > 0 ? Math.round(spent * 100 / e.allocated) : 0 });
  }
  function snapshot(s, now) {
    const accounts = Array.from(new Set(s.transactions.map(t => t.account).concat(s.anchors.map(a => a.account), s.envelopes.map(e => e.account))));
    const envelopes = s.envelopes.map(e => envelopeView(s, e));
    const accountViews = accounts.map(account => {
      const b = balance(s, account), reserved = envelopes.filter(e => e.account === account).reduce((sum, e) => sum + e.remaining, 0);
      return { account, balance: b.amount, balanceDate: b.date, origin: b.origin, reserved, available: b.amount === null ? null : b.amount - reserved };
    });
    const month = new Date(new Date(now || new Date()).getTime() + 4 * 3600000).toISOString().slice(0, 7);
    const ts = s.transactions.filter(t => !t.dateEstimated && !t.excluded && new Date(at(t) + 4 * 3600000).toISOString().slice(0, 7) === month);
    const expenses = ts.filter(t => outgoing(t.kind)).reduce((v, t) => v + t.amount, 0), refunds = ts.filter(t => t.kind === 'refund').reduce((v, t) => v + t.amount, 0);
    const income = ts.filter(t => ['income', 'incoming', 'deposit'].includes(t.kind)).reduce((v, t) => v + t.amount, 0), categories = {};
    ts.forEach(t => { if (outgoing(t.kind) || t.kind === 'refund') categories[t.category] = (categories[t.category] || 0) + (t.kind === 'refund' ? -t.amount : t.amount); });
    const alerts = [];
    accountViews.forEach(a => {
      if (a.balance !== null && a.balance <= s.settings.lowBalance) alerts.push({ id: 'low-' + a.account, title: 'الرصيد منخفض', detail: 'المتبقي ' + format(a.balance) + ' ر.ع', level: 'warning' });
      if (a.available !== null && a.available < 0) alerts.push({ id: 'allocation-' + a.account, title: 'التوزيع يتجاوز الرصيد', detail: 'خفّض مخصصاتك بمقدار ' + format(-a.available) + ' ر.ع', level: 'danger' });
      const dated = s.transactions.filter(t => t.account === a.account && !t.dateEstimated && t.bankBalance != null).sort((x, y) => at(x) - at(y));
      if (dated.some((t, i) => i > 0 && dated[i - 1].bankBalance + s.transactions.filter(x => x.account === a.account && !x.dateEstimated && at(x) > at(dated[i - 1]) && at(x) <= at(t)).reduce((sum, x) => sum + signed(x), 0) !== t.bankBalance))
        alerts.push({ id: 'gap-' + a.account, title: 'السجل يحتاج مطابقة', detail: 'توجد حركة غير مستوردة أو فرق في الرصيد المتاح. الرصيد مستند إلى آخر رسالة مؤرخة.', level: 'info' });
    });
    envelopes.filter(e => e.allocated > 0 && e.percent >= s.settings.warningPercent).forEach(e => alerts.push({ id: 'envelope-' + e.id, title: e.percent >= 100 ? 'وصلت إلى حد ' + e.name : 'اقتربت من حد ' + e.name, detail: 'صرفت ' + format(e.spent) + ' من ' + format(e.allocated) + ' ر.ع', level: e.percent >= 100 ? 'danger' : 'warning' }));
    const netExpense = Math.max(0, expenses - refunds);
    if (s.settings.monthlyLimit > 0 && netExpense * 100 >= s.settings.monthlyLimit * s.settings.warningPercent) alerts.push({ id: 'monthly-' + month, title: 'تنبيه حد المصروف الشهري', detail: format(netExpense) + ' من ' + format(s.settings.monthlyLimit) + ' ر.ع', level: 'warning' });
    const pending = s.transactions.filter(t => t.dateEstimated).length;
    if (pending) alerts.push({ id: 'dates', title: 'عمليات تحتاج تاريخاً', detail: String(pending) + ' عملية بلا تاريخ. أكّد تاريخها لتدخل في الرصيد والتقرير.', level: 'info' });
    return { accounts: accountViews, envelopes, alerts, expenses, refunds, netExpense, income, pending, month, categories: Object.keys(categories).map(name => ({ name, amount: categories[name] })).sort((a, b) => b.amount - a.amount) };
  }
  function validate(s) {
    if (!s || s.version !== 1 || !Array.isArray(s.transactions) || !Array.isArray(s.envelopes) || !Array.isArray(s.anchors) || !Array.isArray(s.rules) || !s.settings) throw new Error('ملف البيانات غير مدعوم.');
    units(s.settings.lowBalance, true); units(s.settings.monthlyLimit, true);
    if (!Number.isInteger(s.settings.warningPercent) || s.settings.warningPercent < 1 || s.settings.warningPercent > 100) throw new Error('نسبة التنبيه غير صالحة.');
    const ids = new Set();
    s.envelopes.forEach(e => { if (!e.id || ids.has(e.id) || !e.name || !e.account || !['saving', 'spending'].includes(e.kind)) throw new Error('مخصص مالي غير صالح.'); ids.add(e.id); units(e.allocated, true); });
    const tids = new Set();
    s.transactions.forEach(t => {
      if (!t.id || tids.has(t.id) || !kinds.includes(t.kind) || !t.account || !t.category || typeof t.dateEstimated !== 'boolean' || typeof t.excluded !== 'boolean') throw new Error('عملية غير صالحة.');
      tids.add(t.id); units(t.amount, false); iso(t.occurredAt); iso(t.receivedAt); if (t.bankBalance != null) units(t.bankBalance, true);
      if (t.envelopeID && !s.envelopes.some(e => e.id === t.envelopeID && e.account === t.account)) throw new Error('مخصص العملية لا يطابق الحساب.');
    });
    s.anchors.forEach(a => { if (!a.account) throw new Error('حساب غير صالح.'); units(a.amount, true); iso(a.date); });
    s.rules.forEach(r => { if (!r.keyword || !r.category || (r.envelopeID && !ids.has(r.envelopeID))) throw new Error('قاعدة تصنيف غير صالحة.'); }); return s;
  }
  function perform(req) {
    const state = req.state ? validate(JSON.parse(JSON.stringify(req.state))) : emptyState(), now = iso(req.now || new Date()), p = req.payload || {}; let result = {};
    switch (req.action) {
      case 'snapshot': break;
      case 'import': {
        const parsed = parse(p.text, p.receivedAt || now); let added = 0, duplicates = 0;
        parsed.transactions.forEach(t => {
          if (state.transactions.some(x => x.id === t.id || ((!x.transactionID || !t.transactionID) && x.fingerprint && x.fingerprint === t.fingerprint))) { duplicates++; return; }
          const r = state.rules.find(r => normalized(t.party).toLowerCase().includes(normalized(r.keyword).toLowerCase()));
          if (r) { t.category = r.category; if (r.envelopeID && state.envelopes.some(e => e.id === r.envelopeID && e.account === t.account)) t.envelopeID = r.envelopeID; }
          state.transactions.push(t); added++;
        }); result = { added, duplicates, errors: parsed.errors }; break;
      }
      case 'manual': {
        const account = normalized(p.account).toUpperCase(); if (!account || !['expense', 'income'].includes(p.kind)) throw new Error('اختر الحساب ونوع العملية.');
        state.transactions.push({ id: 'manual-' + digest(now + JSON.stringify(p) + Math.random()), fingerprint: null, transactionID: null, account, kind: p.kind,
          amount: money(p.amount), bankBalance: null, party: normalized(p.party) || 'عملية يدوية', occurredAt: iso(p.date || now), receivedAt: now, dateEstimated: false,
          category: normalized(p.category) || 'أخرى', envelopeID: p.envelopeID || null, excluded: false, source: 'manual' }); break;
      }
      case 'anchor': {
        const account = normalized(p.account).toUpperCase(); if (!account) throw new Error('أدخل رقم الحساب أو اسمه.');
        state.anchors = state.anchors.filter(a => a.account !== account); state.anchors.push({ account, amount: money(p.amount, true), date: iso(p.date || now) }); break;
      }
      case 'envelope': {
        const name = normalized(p.name), account = normalized(p.account).toUpperCase(); if (!name || !account) throw new Error('أدخل اسم المخصص واختر الحساب.');
        if (!['saving', 'spending'].includes(p.kind)) throw new Error('نوع المخصص غير صالح.');
        const id = p.id || 'pot-' + digest(now + name + Math.random()), old = state.envelopes.find(e => e.id === id);
        if (old && old.account !== account) throw new Error('لا يمكن نقل المخصص إلى حساب مختلف.');
        const e = { id, name, account, kind: p.kind, allocated: money(p.amount, true) }, current = balance(state, account).amount;
        const others = state.envelopes.filter(e => e.account === account && e.id !== id).reduce((v, e) => v + envelopeView(state, e).remaining, 0);
        if (current === null) throw new Error('ثبّت رصيد الحساب أولاً برسالة مؤرخة أو بإدخاله يدوياً.');
        if (others + envelopeView(state, e).remaining > current) throw new Error('المبلغ المطلوب يتجاوز الرصيد المتاح للتوزيع.');
        state.envelopes = state.envelopes.filter(e => e.id !== id).concat(e); break;
      }
      case 'deleteEnvelope': state.envelopes = state.envelopes.filter(e => e.id !== p.id); state.transactions.forEach(t => { if (t.envelopeID === p.id) t.envelopeID = null; }); state.rules.forEach(r => { if (r.envelopeID === p.id) r.envelopeID = null; }); break;
      case 'editTransaction': {
        const t = state.transactions.find(t => t.id === p.id); if (!t) throw new Error('العملية غير موجودة.');
        if (p.category !== undefined) t.category = normalized(p.category) || 'أخرى'; if (p.envelopeID !== undefined) t.envelopeID = p.envelopeID || null;
        if (p.excluded !== undefined) t.excluded = !!p.excluded; if (p.date) { t.occurredAt = iso(p.date); t.dateEstimated = false; } break;
      }
      case 'deleteTransaction': state.transactions = state.transactions.filter(t => t.id !== p.id); break;
      case 'rule': {
        const keyword = normalized(p.keyword), category = normalized(p.category); if (!keyword || !category) throw new Error('أدخل اسم الجهة والتصنيف.');
        state.rules = state.rules.filter(r => r.keyword.toLowerCase() !== keyword.toLowerCase()).concat({ keyword, category, envelopeID: p.envelopeID || null }); break;
      }
      case 'deleteRule': state.rules = state.rules.filter(r => r.keyword !== p.keyword); break;
      case 'settings': state.settings = { lowBalance: money(p.lowBalance, true), monthlyLimit: money(p.monthlyLimit, true), warningPercent: Number(p.warningPercent) }; break;
      case 'restore': { const s = validate(typeof p.data === 'string' ? JSON.parse(p.data) : p.data); return { state: s, snapshot: snapshot(s, now), result: { restored: true } }; }
      default: throw new Error('الإجراء غير مدعوم.');
    }
    validate(state); return { state, snapshot: snapshot(state, now), result };
  }
  root.MizaniCore = { normalized, money, format, parse, balance, snapshot, emptyState, perform, validate };
  root.mizaniExecute = json => { try { return JSON.stringify({ ok: true, data: perform(JSON.parse(json)) }); } catch (e) { return JSON.stringify({ ok: false, error: e.message || 'حدث خطأ غير متوقع.' }); } };
  if (typeof module !== 'undefined' && module.exports) module.exports = root.MizaniCore;
})(typeof globalThis !== 'undefined' ? globalThis : this);
