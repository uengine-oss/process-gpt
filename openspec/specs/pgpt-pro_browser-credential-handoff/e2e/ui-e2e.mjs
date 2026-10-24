// UI E2E: the real pgpt-pro app (:5180 → BFF :8787) and the real model drive a browser task on a
// local test shop. The script plays the user in the chat UI and collects evidence into results/.
//
//   1) login request  → the user enters credentials in the chat vault card → saved to the vault
//   2) one-time code  → entered in a secret card, typed into the page, never stored
//   3) card request   → the user enters a card → saved → filled server-side → approval card → paid
//   4) settings       → accounts / wallet / security (encryption check + vault activity)
//   5) evidence       → independent KEK→DEK→item decryption of the stored rows, model-trace leak scan,
//                       what the shop actually received
//
// Run (BFF must have been started with PRO_LLM_TRACE=<file> to scan what the model saw):
//   PRO_LLM_TRACE=/path/trace.jsonl node openspec/specs/pgpt-pro_browser-credential-handoff/e2e/ui-e2e.mjs
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

const here = path.dirname(fileURLToPath(import.meta.url))
const PRO = process.env.PGPT_PRO_DIR || '../process-gpt-lite'
const APP = process.env.APP_URL || 'http://localhost:5180'
const API = process.env.API_URL || 'http://localhost:8787'
const SHOP_PORT = Number(process.env.SHOP_PORT || 8799)
const TRACE = process.env.PRO_LLM_TRACE || ''
const OUT = path.join(here, 'results')
fs.mkdirSync(OUT, { recursive: true })

const { chromium } = await import(`${PRO}/server/node_modules/playwright/index.mjs`)
const requirePro = createRequire(`${PRO}/server/package.json`)
const pg = requirePro('pg')
const dotenv = requirePro('dotenv')
const { startShop, SHOP } = await import(`${PRO}/server/test/fixtures/shop.mjs`)

const env = { ...dotenv.parse(fs.readFileSync((process.env.PGPT_ROOT || '.') + '/.env')), ...dotenv.parse(fs.readFileSync(`${PRO}/server/.env`)) }
const db = new pg.Pool({ host: '127.0.0.1', port: 54322, user: 'postgres', password: env.POSTGRES_PASSWORD, database: 'postgres' })
const q = (t, p) => db.query(t, p).then((r) => r.rows)

const CARD = { name: 'HONG GILDONG', number: '4242424242424242', exp: '12/30', cvv: '123' }
const SECRETS = [SHOP.password, SHOP.otp, CARD.number, '4242 4242 4242 4242']
const steps = []
const log = (name, ok, detail = {}) => { steps.push({ name, ok, ...detail }); console.log(`${ok ? '✔' : '✖'} ${name}`, Object.keys(detail).length ? JSON.stringify(detail) : '') }
const shot = (page, name) => page.screenshot({ path: path.join(OUT, `${name}.png`) })

const shop = await startShop(SHOP_PORT, { cards: [CARD] })
const email = `vault-e2e-${Date.now()}@uengine.org`
const login = await (await fetch(`${API}/api/auth/email/verify`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, code: '000000' }) })).json()
const userId = login.user.id
await q(`update pro_profile set onboarded_at=now(), birth='1990-01-01', name='볼트 검증' where user_id=$1`, [userId])
const traceStart = TRACE && fs.existsSync(TRACE) ? fs.statSync(TRACE).size : 0

const browser = await chromium.launch({ headless: true })
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1.5, locale: 'ko-KR', recordVideo: { dir: OUT, size: { width: 1280, height: 800 } } })
await ctx.addInitScript((s) => localStorage.setItem('pgpt-pro-session', JSON.stringify(s)), { user: login.user, session: login.session })
const page = await ctx.newPage()
await page.goto(`${APP}/chat`)
await page.waitForSelector('textarea', { timeout: 30000 })

async function send(text) {
  await page.fill('textarea', text)
  await page.click('button[aria-label="보내기"]')
}
// the newest card of a given kind, as rendered
const lastVault = () => page.locator('form.vault').last()
async function waitFor(fn, ms, every = 1000) {
  const end = Date.now() + ms
  while (Date.now() < end) { const v = await fn(); if (v) return v; await page.waitForTimeout(every) }
  return null
}
const taskState = async () => (await q(`select m.content->>'state' s from pro_messages m join pro_threads t on t.id=m.thread_id where t.user_id=$1 and m.kind='task' order by m.created_at desc limit 1`, [userId]))[0]?.s
const pendingCard = async () => (await q(`select m.id, m.kind, m.content from pro_messages m join pro_threads t on t.id=m.thread_id
  where t.user_id=$1 and m.kind in ('vault','choice') and m.content->>'state'='pending' order by m.created_at desc limit 1`, [userId]))[0]

try {
  // ---------- 1) login request ----------
  await send(`테스트 상점(${shop.url}/login)에 로그인해서 내 최근 주문 내역을 알려줘.`)
  const req = await waitFor(async () => { const c = await pendingCard(); return c?.kind === 'vault' && (c.content.kind || 'login') === 'login' ? c : null }, 180000)
  log('브라우저 에이전트가 비밀번호 입력란에서 멈추고 채팅에 보관함 로그인 카드를 올림', !!req, { site: req?.content.site, mode: req?.content.mode })
  if (!req) throw new Error('no login request card')
  await page.waitForTimeout(800)
  await shot(page, '01-login-request-card')
  const form = lastVault()
  await form.locator('input[autocomplete="username"]').fill(SHOP.username)
  await form.locator('input[type="password"]').fill(SHOP.password)
  await shot(page, '02-login-card-filled')
  await form.locator('button.dark-btn').click()
  await page.getByText('로그인 저장됨').last().waitFor({ timeout: 15000 })
  log('사용자가 입력한 로그인이 보관함에 저장되고 카드가 "로그인 저장됨"으로 바뀜', true)
  await shot(page, '03-login-saved-chip')

  // ---------- 2) one-time code ----------
  const otp = await waitFor(async () => {
    const c = await pendingCard()
    if (c?.content.kind === 'secret') return c
    return (await taskState()) === 'done' ? 'done' : null
  }, 180000)
  if (otp && otp !== 'done') {
    await page.waitForTimeout(800)
    await shot(page, '04-otp-secret-card')
    await lastVault().locator('input').fill(SHOP.otp)
    await lastVault().locator('button.dark-btn').click()
    log('일회용 인증 코드 요청 카드가 뜨고, 입력한 값이 페이지에 바로 입력됨(저장 안 함)', true)
  } else {
    log('일회용 인증 코드 요청 카드', false, { note: otp === 'done' ? 'task finished without asking' : 'timeout' })
  }
  const done1 = await waitFor(async () => ['done', 'failed', 'cancelled'].includes(await taskState()) && (await taskState()), 240000)
  await page.waitForTimeout(1500)
  await shot(page, '05-login-task-done')
  log('로그인 작업 완료', done1 === 'done', { state: done1, shop_logins: shop.state.logins.map((l) => l.passwordOk), shop_otps: shop.state.otps.map((o) => o.ok) })

  // ---------- 3) card checkout ----------
  await send(`테스트 상점(${shop.url}/checkout)에서 무선 이어폰을 결제해줘. 결제 버튼을 누르기 전에 꼭 나에게 승인을 받아.`)
  const creq = await waitFor(async () => { const c = await pendingCard(); return c?.content.kind === 'card' ? c : null }, 180000)
  log('결제 카드 입력란에서 멈추고 채팅에 카드 등록 카드를 올림', !!creq)
  if (!creq) throw new Error('no card request')
  await page.waitForTimeout(800)
  await shot(page, '06-card-request-card')
  const cf = lastVault()
  await cf.locator('input[autocomplete="cc-name"]').fill(CARD.name)
  await cf.locator('input[autocomplete="cc-number"]').pressSequentially(CARD.number)
  await cf.locator('input[autocomplete="cc-exp"]').pressSequentially('1230')
  await cf.locator('input[autocomplete="cc-csc"]').fill(CARD.cvv)
  await shot(page, '07-card-filled')
  await cf.locator('button.dark-btn').click()
  await page.getByText('카드 저장됨').last().waitFor({ timeout: 15000 })
  log('카드가 보관함에 저장되고 "카드 저장됨 · Visa •••• 4242" 로 바뀜', true)

  const approval = await waitFor(async () => { const c = await pendingCard(); return c?.kind === 'choice' && c.content.approval ? c : null }, 240000)
  log('결제 직전 승인 카드(금액·카드 라벨)가 뜸', !!approval, { question: approval?.content.question })
  if (approval) {
    await page.waitForTimeout(1000)
    await shot(page, '08-approval-card-masked-fields')
    // the live screen with the filled card fields, enlarged
    await page.locator('.task .screen').last().screenshot({ path: path.join(OUT, '09-live-browser-card-fields.png') }).catch(() => {})
    await page.locator('.choice button.dark-btn').last().click()
  }
  const done2 = await waitFor(async () => ['done', 'failed', 'cancelled'].includes(await taskState()) && (await taskState()), 240000)
  await page.waitForTimeout(1500)
  await shot(page, '10-payment-done')
  log('결제 작업 완료 · 상점이 받은 카드가 저장한 카드와 일치', done2 === 'done' && shop.state.payments.some((p) => p.ok), { state: done2, payments: shop.state.payments })

  // ---------- 4) settings ----------
  for (const [p, name] of [['accounts', '11-settings-accounts'], ['wallet', '12-settings-wallet'], ['security', '13-settings-security']]) {
    await page.goto(`${APP}/settings/${p}`)
    await page.waitForTimeout(1500)
    if (p === 'security') {
      await page.getByRole('button', { name: '검증' }).click()
      await page.getByText('모든 항목 통과').waitFor({ timeout: 10000 }).catch(() => {})
      await page.waitForTimeout(500)
      await shot(page, name)
      // the settings sheet scrolls inside itself: capture the proof rows and the activity log too
      await page.getByText('모든 항목 통과').evaluate((e) => e.scrollIntoView({ block: 'start' })).catch(() => {})
      await shot(page, '14-security-proof-detail')
      await page.getByText('보관함 활동').scrollIntoViewIfNeeded().catch(() => {})
      await page.locator('.settings').evaluate((e) => e.scrollBy(0, 400)).catch(() => {})
      await shot(page, '15-security-vault-activity')
    } else await shot(page, name)
  }
  log('설정 화면(계정·지갑·보안) 확인', true)
} catch (e) {
  log('중단', false, { error: e.message })
  await shot(page, '99-error').catch(() => {})
}

// ---------- 5) evidence ----------
const keys = await q('select user_id, kek_id, dek_version, wrapped_dek from pro_vault_keys where user_id=$1', [userId])
const items = await q('select id, kind, site, label, status, fingerprint, secret, meta, use_count from pro_vault_items where user_id=$1 order by kind', [userId])
const audit = await q('select action, kind, site, actor, detail, created_at from pro_vault_audit where user_id=$1 order by created_at', [userId])

// independent decryption with the server keyring: KEK → DEK → item (prints booleans only)
const ring = JSON.parse(fs.readFileSync(`${PRO}/server/.vault-keyring.json`, 'utf8'))
const kek = Buffer.from(ring.keys.find((k) => k.id === keys[0]?.kek_id)?.key || '', 'base64')
const open = (key, blob, aad) => {
  const b = Buffer.from(blob, 'base64')
  const d = crypto.createDecipheriv('aes-256-gcm', key, b.subarray(0, 12))
  d.setAAD(Buffer.from(aad)); d.setAuthTag(b.subarray(12, 28))
  return Buffer.concat([d.update(b.subarray(28)), d.final()])
}
const independent = {}
try {
  const k = keys[0]
  const dek = open(kek, k.wrapped_dek, k.dek_version > 1 ? `dek:${userId}:v${k.dek_version}` : `dek:${userId}`)
  independent.dek_unwrapped_with_kek = dek.length === 32
  for (const it of items) {
    const data = JSON.parse(open(dek, it.secret, `item:${userId}:${it.kind}:${it.site}`).toString())
    if (it.kind === 'login') independent.login_matches_what_user_typed = data.username === SHOP.username && data.password === SHOP.password
    if (it.kind === 'card') independent.card_matches_what_user_typed = data.number === CARD.number && data.cvv === CARD.cvv && data.exp === CARD.exp
    independent[`${it.kind}_not_openable_with_kek_directly`] = (() => { try { open(kek, it.secret, `item:${userId}:${it.kind}:${it.site}`); return false } catch { return true } })()
  }
} catch (e) { independent.error = e.message }
const rowsText = JSON.stringify([keys, items])
const plaintextInDb = SECRETS.filter((s) => rowsText.includes(s) || rowsText.includes(Buffer.from(s).toString('base64')))

let leak = { trace: TRACE || null }
if (TRACE && fs.existsSync(TRACE)) {
  const text = fs.readFileSync(TRACE, 'utf8').slice(traceStart)
  const lines = text.split('\n').filter(Boolean)
  const mine = lines.filter((l) => l.includes(shop.url) || l.includes('127.0.0.1:' + SHOP_PORT))
  leak = { trace: path.basename(TRACE), model_requests_in_run: lines.length, model_requests_about_shop: mine.length, secrets_found: SECRETS.filter((s) => text.includes(s)).length }
}
const vaultApi = await (await fetch(`${API}/api/vault`, { headers: { Authorization: `Bearer ${login.session.access_token}` } })).json()
const proof = await (await fetch(`${API}/api/vault/proof`, { headers: { Authorization: `Bearer ${login.session.access_token}` } })).json()

const results = {
  ran_at: new Date().toISOString(), app: APP, api: API, shop: shop.url, user: { id: userId, email },
  steps,
  shop_received: { logins: shop.state.logins.map(({ username, passwordOk }) => ({ username, passwordOk })), otps: shop.state.otps.map(({ ok }) => ({ ok })), payments: shop.state.payments.map(({ last4, ok }) => ({ last4, ok })) },
  database: {
    pro_vault_keys: keys.map((k) => ({ kek_id: k.kek_id, dek_version: k.dek_version, wrapped_dek: `${k.wrapped_dek.slice(0, 24)}… (${Buffer.from(k.wrapped_dek, 'base64').length} bytes)` })),
    pro_vault_items: items.map((i) => ({ kind: i.kind, site: i.site, label: i.label, status: i.status, meta: i.meta, use_count: i.use_count, fingerprint: i.fingerprint, secret: `${i.secret.slice(0, 24)}… (${Buffer.from(i.secret, 'base64').length} bytes)` })),
    plaintext_secrets_found_in_rows: plaintextInDb.length,
  },
  independent_envelope_check: independent,
  api_list_returns_secret_fields: vaultApi.some((v) => 'secret' in v || 'password' in v || 'number' in v),
  api_proof: { ok: proof.ok, kek: proof.kek, dek: { version: proof.dek?.version, wrapped_bytes: proof.dek?.wrapped_bytes }, items: proof.items?.map((i) => ({ kind: i.kind, label: i.label, checks: i.checks })) },
  model_trace_leak_scan: leak,
  audit: audit.map((a) => ({ action: a.action, kind: a.kind, site: a.site, actor: a.actor, field: a.detail?.field, at: a.created_at })),
}
fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify(results, null, 2))
console.log(JSON.stringify({ independent_envelope_check: independent, plaintext_in_db: plaintextInDb.length, leak, shop_received: results.shop_received }, null, 2))

await ctx.close()
const video = fs.readdirSync(OUT).find((f) => f.endsWith('.webm'))
if (video) fs.renameSync(path.join(OUT, video), path.join(OUT, 'ui-e2e.webm'))
await browser.close()
await shop.close()
await db.end()
process.exit(steps.every((s) => s.ok) ? 0 : 1)
