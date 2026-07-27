# Roast My Gallery — App Store gönderimi: kalan işler

> Bu dosya yeni bir Claude sohbetine devretmek için yazıldı. Kendi kendine
> yeterli olacak şekilde hazırlandı — önceki sohbetin bağlamı olmadan da
> okunabilir. Gönderim tamamlanınca silinebilir.

---

## Bağlam

**Roast My Gallery** — iOS uygulaması. Fotoğraf kütüphanesini **cihaz üzerinde**
(Vision) analiz ediyor, çıkan anonim istatistiklerden Google Gemini ile mizahi
bir "roast" ya da yumuşak bir analiz metni yazdırıyor, paylaşılabilir kart
üretiyor.

- **Monetizasyon:** RevenueCat Virtual Currency ("gems"). 3 tüketilebilir paket
  (`credits_pack_10/40/120`). 1 gem = Standard analiz, 5 gem = Deep analiz.
  İlk açılışta **6** bedava gem — bilerek `deep + standard` toplamı, böylece
  yeni kullanıcı (ve reviewer) her iki katmanı da parasız deneyebiliyor.
- **Backend:** `backend/` — Vercel serverless, Gemini'yi sarmalıyor. Testler:
  `cd backend && npm test` (şu an 12/12).
- **Web sitesi:** `roastmygallery.unlertu.workers.dev` — assets-only Cloudflare
  Worker, adı `roastmygallery`. **Kaynağı `site/` altında** (bkz. `site/README.md`).
  `/privacy/`, `/terms/`, `/support/` yayında ve güncel.
- **Apple ID:** 6791121107 · **Bundle:** `com.ertugrul.RoastMyGallery`

### Çalışma kuralları

- `CLAUDE.md`: **uygulamayı asla derleme/çalıştırma.** Önceki oturumda kullanıcı
  bir kereliğine izin verdi; yeni oturumda tekrar sorulmalı.
- Swift dosyası **eklenince/silinince** `xcodegen generate` çalıştır (derleme
  değil, sadece proje dosyası bakımı — bu serbest).
- Legal metinler `legal/` altında; canlı sayfalar Worker'dan servis ediliyor.

---

## ✅ Tamamlananlar — tekrar yapılmasına gerek yok

| Konu | Ne yapıldı |
|---|---|
| Guideline 2.1 | "Coming soon"/"SOON" placeholder UI'ları kaldırıldı (Home kartı, InsightView butonu, Settings Appearance satırı, History filtresi) |
| Guideline 2.1 | Starter grant sessiz başarısızlığı düzeltildi — kullanıcı artık 0 gem'de kilitlenmiyor, backend `reason` alanı döndürüyor, client `granted`'ı okuyor |
| Guideline 1.2 | "Report this analysis" akışı eklendi (`SupportMail` + sonuç ekranında satır) |
| Guideline 3.1.1 | Gem'ler iCloud Keychain ile yeni telefona geçiyor (`KeychainAppUserID`, migration'lı) |
| Guideline 5.1.1 / GDPR | **Deep Analysis onay kapısı** — yüklenecek fotoğraflar kullanıcıya gösteriliyor, çıkarılabiliyor, reddedilebiliyor (`CaptionReviewView`) |
| Doğruluk | "hand-pick / you approve" yanlış iddiaları düzeltildi (4 ekran + gizlilik politikası) |
| Doğruluk | Gemini **paid tier** taahhüdü metinlere işlendi ("hiçbir AI modelini eğitmek için kullanılmaz") |
| 2.1 | `mailto:` başarısızlığında adres gösteren yedek uyarı (mail hesabı olmayan cihaz = ölü buton riski) |
| — | İzin ekranına Terms/Privacy satırı; URL'ler `AppConfig`'e toplandı |
| — | ToS'tan olmayan abonelik/lifetime metni çıkarıldı; README yeniden yazıldı; `legal/*.md` canlıyla senkronlandı |
| — | Swift 6'da hard error olacak actor-isolation uyarısı düzeltildi |

Debug + Release derleniyor, 0 uyarı. Ship-guard geçiyor.

---

## ✅ Claude'un iki işi — 2026-07-26'da tamamlandı

### 1. Tüm uygulama metin taraması — bitti

- **[PaywallView.swift:182](RoastMyGallery/Views/PaywallView.swift#L182)** +
  **[HomeView.swift:257](RoastMyGallery/Views/Home/HomeView.swift#L257)** —
  *"an AI caption on every photo"* kaldırıldı. Üç sebepten yanlıştı: caption
  toggle'ı varsayılan kapalı, onay ekranında fotoğraf çıkarılabiliyor, ve
  caption en fazla **12** fotoğrafa gidiyor (beat başına bir tane,
  `ScanViewModel.captionTargets` `maxBatchSize` ile kırpıyor).
- **[PaywallView.swift:167](RoastMyGallery/Views/PaywallView.swift#L167)** —
  *TODO'da yoktu.* Standard tier *"Full-history scan"* diyordu ama
  `PersonaPickerView.canStart` ay/albüm seçilmeden başlatmıyor; `.fullHistory`
  scope'u UI'dan erişilemiyor. Aynı 2.3.2 sınıfı yanlış vaat, düzeltildi.
- **[ScanProgressView.swift:66](RoastMyGallery/Views/ScanFlow/ScanProgressView.swift#L66)**
  — *"Adding a note under each photo…"* → *"…to the photos you approved…"*.

Geri kalan tarama temiz çıktı: Deep Vision atıflarının hepsi
`AnalysisKind.launchable` arkasında, dört gizlilik metni (PermissionView,
PersonaPickerView, SettingsView, DataTransparencyView) onay kapısını doğru
anlatıyor. `AnalysisStatusBanner:67` bir iddia içermediği için değişmedi.

### 2. Legal sayfalar — handoff'a gerek kalmadı, doğrudan deploy edildi

Eski handoff'un üç bölümü de canlıda **zaten uygulanmıştı** (`/support/` yayında,
`/privacy/` iCloud Keychain doğru, `/terms/` bölüm 6 temiz). Kalan 8 düzenleme
`site/`'tan doğrudan deploy edildi — version `ac446486`, canlıda doğrulandı:
`Deep Vision` ve `hand-pick` dört sayfanın hiçbirinde yok, onay kapısı ve Gemini
paid-tier paragrafları yerinde.

**Ek bulgu:** önceki oturum `Deep Vision`'ı gizlilik politikasının §1 ve
§3.3'ünden çıkarmış ama §4, §5 tablosu, §7 ve ToS §5'te bırakmış — sayfa kendi
kendiyle çelişiyordu. Hem `legal/*.md`'de hem canlıda tamamlandı.

`legal/support-page-handoff.md` artık OBSOLETE damgalı, kimseye gönderilmemeli.

---

## ✅ 2026-07-27 oturumu — yapılanlar

Hepsi kodda, **hiçbiri commit'lenmedi ve backend deploy edilmedi** (bkz. aşağıdaki
"Hemen yapılacaklar").

| Konu | Ne yapıldı |
|---|---|
| Rate bildirimi | Otomatik App Store puanlama isteği eklendi (`ReviewPrompter.swift` — ≥2 tamamlanmış analiz, sürüm başına bir kez, sonuç ekranında 2 sn gecikmeli). Ayarlar'daki "Rate this app" ise artık `requestReview()` yerine App Store yorum sayfasını **doğrudan** açıyor (Apple sistem penceresini yılda ~3 kez gösterip sonra sessizce yutuyor; butona basan hep bir şey görmeli) |
| App Store ID | `6791121107` işlendi — Share linki ve Rate linki. Sahte `id0000000000` gitti |
| project.yml | `DEVELOPMENT_TEAM: J7L764Z34L`, `MARKETING_VERSION: "1.0"`, bundle ID notu. Artık `xcodegen generate` imza ayarını silmiyor |
| Paywall | Kapalı özelliği satıyordu ("5 gems = 1 Deep Vision batch") → **Deep Analysis**'e çevrildi. Paket kartı alt yazısı sadeleşti: "= 40 analyses" |
| StoreKit config | `credits_pack_20/50` → `credits_pack_10/40` (koddaki paketlerle eşleşiyordu değil) |
| Starter grant | **Sunucu taraflı kalıcı tekilleştirme** (`claimOnce`/`releaseOnce` — reinstall veya elle istek artık +6 gem veremiyor). Grant başarısız olursa claim geri bırakılıyor, kullanıcı hakkını kaybetmiyor. 2 yeni test |
| Bildirimler | Haftalık genel hatırlatıcı → **aylık recap + uzaklaşma dürtmesi**. Detay aşağıda |
| Az foto uyarısı | Ay ve tarih-aralığı seçicilerinde canlı fotoğraf sayısı + uyarı. Detay aşağıda |
| AI güvenliği | Fotoğraf gören iki uç noktaya (`photo-captions`, `deep-vision`) `safetySettings` **MEDIUM** seviyesinde sabitlendi |

### Bildirim mantığı — neden değişti

Eskisi: her Pazar 11:00, *"This week's photos are waiting to be roasted."*
İki sorunu vardı. Birincisi metin **ürünün yapamadığı bir şeyi** vaat ediyordu —
Standard analiz haftayı analiz edemiyor, `PersonaPickerView.canStart` ay veya
albüm istiyor. İkincisi genel bir mesajı sık göndermek açılma oranını değil
**kapatma oranını** artırır, ve iOS'ta bildirimi kapatan kullanıcı kalıcı olarak
kaybedilir.

Yenisi (`ReminderScheduler.swift`, tek Ayarlar anahtarının arkasında):
1. **Aylık recap** — her ayın 1'inde 11:00, biten ayın **adıyla** ("April is a
   wrap"). Ürünün gerçek birimiyle (ay) örtüşüyor. Ay adını taşıyabilmesi için
   6 ay ileri tek tek planlanıyor, her açılışta `refresh()` ile yenileniyor.
2. **Uzaklaşma dürtmesi** — son analizden 14 gün sonra, tek seferlik. Her
   tamamlanan analizde ileri itiliyor (`noteAnalysisCompleted()`), yani aktif
   kullanıcı hiç almıyor.

Kişi başı ayda 1–2 bildirim. Eşikler dosyanın başındaki sabitlerde.
**Bilinçli olarak bildirimde gem satılmıyor:** Guideline 4.5.4 push'u ayrı
onay olmadan reklam/promosyon için yasaklıyor. Bildirimin işi analiz
yaptırmak; tüketilebilir ekonomide satın alma bakiye bitince kendiliğinden
geliyor.

### Az foto uyarısı — neden eklendi

Backend prompt'u veri ne kadar az olursa olsun **sabit sayıda beat** yazıyor
("even for a small library, write the full 5-7 beats"). Yani 8 fotoğraflık bir
ay kısa hikâye değil, **dolgu** hikâye üretiyor — ve gem tahsil ediliyor.
Ay seçicide fotoğraf sayısı hiç gösterilmiyordu (albüm seçicide gösteriliyor).

`ScopeVolumeNote.swift` + `AnalysisDepth.sufficiency(forPhotoCount:)`:
- **0 foto** → kırmızı uyarı, onay butonu kapalı (o run zaten `emptyLibrary` ile
  patlardı)
- **Eşiğin altı** → turuncu "Only 12 photos — the story will be short", buton
  **açık** (9 fotoluk tatil albümünü okutmak isteyen olabilir; engellemek değil
  beklenti kurmak istiyoruz)
- **Yeterli** → nötr gri sayı

Eşikler: Standard **25**, Deep **120** (Deep 12–16 beat ve ≥8 kategori istiyor,
üstelik 5 gem). Sayım PhotoKit'in tembel `count`'u, 250 ms debounce'lu ayrı
task'ta — tekerlek dönerken UI takılmıyor.

### AI güvenlik ayarı — neden MEDIUM, neden LOW değil

Fotoğraf **sadece** Deep Analysis'in caption adımında AI'a gidiyor (hikâyenin
kendisi hep fotoğrafsız yazılıyor, sadece anonim sayılarla). Yani "görünüşle
dalga geçme" riski **tek** bir yerde var.

`VISION_SAFETY_SETTINGS` (lib/prompts.js) MEDIUM'da sabitlendi. **LOW'a
çekilmedi** çünkü roast, sınıflandırıcı gözünde zaten hafif tacizdir — LOW
sıradan şakaları da bloklardı ve kullanıcı 5 gem verip boş caption görürdü.
Asıl kazanç sıkılık değil, **açıkça sabitlenmiş** olması: Google'ın varsayılanı
model sürümleri arasında sessizce değişebilir.

"Görünüşe yorum yapma" kuralı **kasten filtreye verilmedi** — o bir güvenlik
kategorisi değil, ürün kuralı; hiçbir sınıflandırıcı "cesur kazak seçimi"ni
işaretlemez. O kural prompt'ta iki yerde duruyor (persona bloğu + caption
talimatları).

---

## Senin yapacakların

### ⚠️ Hemen — bu oturumun işi yarım kalmasın

- [x] ✅ **Backend deploy edildi** — 2026-07-27, `dpl_8tVtmzKqLgyHRYs6cPxzRbTzbHtC`.
      `vercel inspect backend-ertu-hobby.vercel.app` ile doğrulandı: uygulamanın
      kullandığı alias yeni deployment'a bakıyor. Gizli anahtarsız istek hâlâ
      401 dönüyor. `safetySettings` artık canlıda.
- [x] ✅ **Xcode'da derlendi, hata yok** — 2026-07-27.
- [x] ✅ **Cihaz testleri, review görselleri, Offering, gem akışı, env
      anahtarları — kullanıcı tarafından tamamlandı** (2026-07-27 beyanı).
      Connect'te "SOON" görünen kare kalmadı.

### Hızlı (birkaç dakika)

- [x] ✅ **Vercel env var'ları tanımlı** (2026-07-27 beyanı): RevenueCat
      anahtarları, `GEMINI_API_KEY`, `APP_SHARED_SECRET`. Gem akışının gerçek
      cihazda çalışması da bunu doğruluyor.
- [x] ✅ **`KV_REST_API_URL` + `KV_REST_API_TOKEN`** — **çözüldü 2026-07-26.**
      Upstash veritabanı (`upstash-kv-citrine-zebra`) `backend` projesine zaten
      bağlıymış, ama **son deployment 9 gün eskiydi** ve env var'ları görmüyordu.
      `vercel --prod` ile yeniden deploy edilince aktifleşti.
      Doğrulandı: sil-kur sonrası ilk grant işareti yazdı
      (`EXISTS once:starter-grant:rmg_...:v1` → `1`), `DBSIZE` > 0.
      Bununla birlikte `runId` ücret tekilliği de aktifleşti — retry'da çift
      gem düşme ihtimali kapandı.
      **Test ederken dikkat:** ilk sil-kur +6 verir ve normaldir; o grant
      işareti yazan grant'tir. Engeli görmek için **ikinci** sil-kur'a bak.

  <details><summary>Sorun tekrarlarsa: açığın mekanizması</summary>

      **Starter grant'in tekrar alınmasını engelleyen tek şey bu.** Zincir:
      `didRequestStarterGrant` UserDefaults'ta → uygulama silinince uçuyor →
      client tekrar istiyor. `rmg_` kimliği Keychain'de kaldığı için aynı
      kullanıcı olarak gidiyor, ve onu durduracak olan backend'deki kalıcı
      `claimOnce` işareti. Ama `claimOnce` KV yoksa `"unknown"` dönüyor
      ([idempotency.js:87](backend/lib/idempotency.js#L87)) ve
      [starter-grant.js:54](backend/api/starter-grant.js#L54) sadece
      `"duplicate"`'te duruyor → **grant tekrar veriliyor.**
      Yani KV set değilken: sil → kur → **+6 gem, sınırsız.** Starter 3'ten 6'ya
      çıktığı için artık her döngü bedava bir Deep analiz demek (en pahalı
      çağrın: güçlü model + 12'ye kadar görsel).
      Kapatınca geriye sadece "Erase All Content" / iCloud Keychain kapalı
      senaryosu kalıyor — tam cihaz sıfırlama maliyeti farming'i pratik olmaktan
      çıkarıyor.

  **Ders:** env var'ları bağlamak yetmiyor, Vercel onları eski deployment'lara
  uygulamıyor. Backend'e env var eklendiğinde `cd backend && vercel --prod`
  şart. Panelden "Redeploy" ise 9 gün önceki KODU yeniden yayınlar — yeni kodu
  canlıya almaz.
  </details>

- [x] ~~Handoff dosyasını siteyi kuran Claude sohbetine gönder~~ — **gerek
      kalmadı.** Legal sayfalar 2026-07-26'da doğrudan deploy edildi (version
      `ac446486`). Site kaynağı artık `site/` altında, repoda.

### App Store Connect

- [ ] **App Privacy nutrition label** — "Data Not Collected" **seçme**:

  | Veri | Kategori | Amaç | Linked |
  |---|---|---|---|
  | Photos or Videos | User Content | App Functionality | Evet |
  | User ID | Identifiers | App Functionality | Evet |
  | Purchase History | Purchases | App Functionality | Evet |
  | Other Data | Other Data | App Functionality | Evet |

  Hepsinde **"Used for Tracking" = Hayır** (izleme SDK'sı yok, doğrulandı).
  "Linked = Evet" çünkü istekler kalıcı `rmg_` kimliğiyle birlikte gidiyor.
  Fazla beyan risksiz, az beyan red sebebi.
  **Konum beyan etme** — cihazdan çıkan tek şey `"cluster-1"` gibi anonim
  etiket + yüzde; koordinat/yer adı yok (koddan doğrulandı).

- [x] ✅ **3 IAP + review screenshot'ları + Offering** — tamamlandı
      (2026-07-27 beyanı). Ürünlerin **sürüme eklenmiş** ve "Ready to Submit"
      olduğunu göndermeden önce bir kez daha doğrula: bu ikisi ayrı adımdır ve
      atlanınca paywall canlıda boş gelir.
- [x] ✅ **Screenshot'lar** — "SOON" görünen kare kalmadı (2026-07-27 beyanı).
- [ ] **Support URL:** `https://roastmygallery.unlertu.workers.dev/support/`
      · **Privacy Policy URL:** `.../privacy/` — ikisi de yayında, 200 dönüyor.
      Connect'teki alanlara girildiğinden emin ol.
- [ ] **Review Notes** — aşağıdaki metni yapıştır. **Guideline 1.2 açısından
      önemli:** rapor yolu (`Report this analysis`) sonuç ekranının en altında,
      caption boyutunda ve gri — bilerek sessiz. Reviewer'ın onu bulmasını
      sağlayan şey bu nottur.

<details>
<summary>Review Notes (hazır metin)</summary>

```
Roast My Gallery analyzes the user's photo library on-device and generates an
AI-written "roast" or a gentler analysis of their photo habits.

NO ACCOUNT — the app has no login, so no demo account is needed.

HOW TO TEST
1. On first launch the app grants 6 free gems automatically. That is enough to
   run BOTH tiers without paying: one Deep analysis (5 gems) and one Standard
   analysis (1 gem). No purchase is required to review any part of the app.
2. Home > "New Analysis" > Standard (1 gem). Pick a month or album that CONTAINS
   PHOTOS, pick a voice (Roast or Analyst), then tap Analyze My Photos.
3. The result screen shows the generated story, a share card, and a
   "Report this analysis" link for reporting generated content.
4. Deep (5 gems) covers a date range and is fully reachable on the free gems.
   Turn on "Caption my photos with AI" to see the consent screen: before any
   photo is uploaded, the app shows the exact photos involved and you can
   approve them, remove individual photos, or decline the batch entirely.

NOTE ON THE TEST DEVICE: photo library access is required for the app's core
function. If the review device has few photos, please choose a month that
contains photos, or grant Full Access so albums can be selected. An empty month
correctly reports "No photos found in the selected time range" and is not
charged.

IN-APP PURCHASES
Three consumable gem packs (credits_pack_10 / credits_pack_40 /
credits_pack_120). Gems are spent per analysis: 1 gem = Standard, 5 gems = Deep.

PRIVACY
A Standard analysis sends only anonymous aggregated statistics — no images, no
identifiers, no location data. Photos leave the device only for the optional
Deep Analysis captions, and only after the user has seen and approved the exact
batch. Uploaded images are processed in memory and are never stored or logged.
```
</details>

### Cihaz testi

- [x] ✅ **Keychain kimliği + satın alım kalıcılığı — doğrulandı 2026-07-26.**
      Kapat-aç testinden daha güçlüsü yapıldı: 40 gem'lik bir sandbox satın
      alımının ardından **uygulama tamamen silinip yeniden kuruldu** ve bakiye
      419'da değişmeden kaldı. Aynı `rmg_` kimliği çözümlendiği için hem
      satın alınan gem'ler korundu (Guideline 3.1.1) hem starter grant tekrar
      verilmedi (KV işareti çalışıyor).
- [x] ✅ **Starter grant tekrarlanmıyor** — yukarıdaki testin ikinci yarısı.
      Aktivasyondan sonraki *ilk* sil-kur +6 vermişti (işareti yazan grant);
      *ikincisi* vermedi. Beklenen davranış bu.
- [x] ✅ Standard analiz → 1 gem düşüyor, hikâye geliyor *(2026-07-27)*
- [x] ✅ Boş ay → "No photos found…" + **gem düşmüyor** *(2026-07-27)*.
      Ücretlendirme başarıdan sonra yapıldığı için boş sonucun "başarı"
      sayılmadığını doğrulayan test buydu.
- [x] ✅ **Deep analiz onay ekranı — doğrulandı 2026-07-27.** Üç yol da denendi
      (*Send* / *Continue without captions* / **X ile kapat**), üçünde de hikâye
      kaydedildi. Gizlilik politikası, App Privacy label'ı ve 5.1.1 duruşunun
      dayandığı ekran bu — artık çalıştığı görülmüş durumda.
- [x] ✅ Sonuç ekranı → "Report this analysis" → mail taslağı açılıyor
      *(2026-07-27)*. Guideline 1.2'nin istediği bildirim yolu.
- [x] ✅ **Paywall + satın alma zinciri — GERÇEK CİHAZDA doğrulandı 2026-07-26.**
      40 gem'lik paket gerçek cihazda sandbox üzerinden satın alındı ve bakiye
      arttı. Bu üçünü birden kanıtlıyor: ürünler yükleniyor (2.1 reddinin en
      yaygın sebebi kapandı), satın alma tamamlanıyor, ve RevenueCat'in sunucu
      tarafı grant'i tetikleniyor — yerel `.storekit` satın alması gem vermezdi.
- [x] ✅ Temiz kurulumda 6 starter gem *(2026-07-27, kullanıcı beyanı)*
- [x] ✅ İkinci cihaz + iCloud Keychain → bakiye geliyor *(2026-07-27, kullanıcı
      beyanı)*

  > Bu son iki madde kullanıcının "hepsi geçti" beyanına dayanıyor. Diğerleri
  > gibi ayrıca gözlemlenmediler — ikisi de özel kurulum istiyor (Simulator'da
  > "Erase All Content and Settings", ya da ikinci bir cihaz). Sorun çıkarsa
  > önce buraya bak.

---

## Açık sorular — release'i bloklamaz, sonra bakılacak

Üçü de 2026-07-27'de incelendi, **bilerek dokunulmadı** (release öncesi
oynanacak şeyler değil). Yeni sohbette gündeme gelirse bağlam burada.

- **Deep sessizce ucuz modele düşebiliyor.** `insight.js` deep için önce
  `gemini-3.5-flash` deniyor, **herhangi bir hatada** `gemini-3.1-flash-lite`'a
  düşüyor. Yani 5 gem ödeyen kullanıcının hikâyesini bazen Standard'ın modeli
  yazıyor — ne kullanıcı anlıyor ne sen. Takas savunulabilir (ödenmiş analizi
  tamamen başarısız etmektense zayıf metin), ama **ne sıklıkta olduğu
  bilinmiyor.** Yayından sonra Vercel loglarında `Gemini 503 on
  gemini-3.5-flash` satırlarını say. Sıksa asıl düzeltilecek şey budur.
  İstenirse yanıta "hangi model yazdı" işareti eklenebilir (kullanıcıya
  görünmez, sadece ölçüm).
- **Vision güven eşiği 0.4** (`OnDeviceAnalyzer.classificationThreshold`).
  Gösterilen fotoğraf için sorun değil (zaten en yüksek güvenli seçiliyor) ama
  **sayıları şişirebilir** — "312 yemek fotoğrafın var" derken bir kısmı 0.41
  güvenli tahmin olabilir. Ürünün tüm güvenilirliği sayıların isabetli
  hissettirmesine bağlı. Kendi galerinde bakıp şişik geliyorsa 0.5'e çıkar.
- **Deep'te `thinkingConfig: { thinkingBudget: 0 }`** (`insight.js`). JSON'un
  yarıda kesilmesini önlemek için konmuştu, ama o sorun `maxOutputTokens`
  1024→8192 ile de çözülmüş. Küçük bir thinking bütçesi Deep'in **konu
  seçimini** iyileştirebilir (metin kalitesini değil — bu bir yazarlık işi,
  muhakeme işi değil). Yayından sonra denenebilir; garanti kazanç değil.

---

## Verilmiş kararlar — yeniden tartışmaya gerek yok

| Karar | Gerekçe |
|---|---|
| Rate/Share linkleri kalıyor | ID doğru; şu an 404 çünkü sayfa public değil, onay sonrası çalışacak. 2.1'in "functional URLs" maddesi metadata URL'lerini hedefliyor |
| Nudity dedektörü (SCSensitivityAnalyzer) **eklenmedi** | `analysisPolicy`, kullanıcının Sensitive Content Warning ayarı kapalıysa `.disabled` dönüyor — yetişkinlerde varsayılan kapalı. Çoğu kullanıcıda hiç çalışmaz, yanlış güven verir. Onay ekranı gerçek çözüm |
| Açılışta sözleşme/onay duvarı **yok** | Hiçbir şey gönderilmeden alınan blanket onay, GDPR'ın istediği "specific ve informed" rızadan daha zayıf. Apple da uygulama içi EULA kabulü istemiyor |
| Bildirme akışı web formu değil, **mail** | Form endpoint + spam + şikâyet metnini sunucuda saklama demek; "kopyasını tutmuyoruz" iddiasıyla çelişirdi |
| Gemini anahtarı **olduğu gibi kalıyor** — ne rotate, ne kısıtlama | Kullanıcının kararı (2026-07-27), iki kez teyit edildi. Depodan sızmadığı doğrulandı: `backend/.env` takipsiz, git geçmişinin tamamında `AIza` dizesi yok. Gönderimi engelleyen bir şey değil. Kotada beklenmedik artış görülürse ilk bakılacak yer burası; o noktada tek gerçek çözüm rotate (yeni anahtar → Vercel `GEMINI_API_KEY` → `vercel --prod`) |
| Destek sayfasındaki 3 taahhüt duruyor | Yanıt süresi, gem iadesi, eski telefon kurtarma yardımı |
| ToS governing law California kalıyor | Canlı sayfayla eşitlendi; hukuki içerik değiştirilmedi |
| Hand-Picked (Deep Vision) **kapalı** | `AnalysisKind.launchable`'da yok. Açmadan önce oradaki nota bak — sonuç ekranlarına "Report" satırı da gerekiyor |
| Bildirimde gem **satılmıyor** | Guideline 4.5.4: push, ayrı uygulama içi onay olmadan reklam/promosyon için kullanılamaz. Bildirim analiz yaptırır; satın alma bakiye bitince gelir |
| Az fotoğraflı ay **engellenmiyor** | Sadece 0 foto butonu kapatıyor. 9 fotoluk albümünü okutmak isteyen olabilir — amaç engellemek değil, beklenti kurmak |
| Açılışta bildirim izni **istenmiyor** | İzin tembel isteniyor (Ayarlar'dan açınca ya da çalışan analiz küçültülünce). Bağlamsız izin isteği reddedilir ve iOS'ta ret kalıcıdır |
| Standard analizde onay ekranı **yok** | Hiç fotoğraf gönderilmiyor; sadece anonim sayılar. Onaylanacak bir şey yok |

---

## Tuzaklar

- **Keychain uygulama silinince silinmiyor** — "sil/yeniden kur" temiz test değil.
- **`/api/starter-grant`'i elle curl'lemek her zaman 502 döner** — uydurma bir
  `rmg_` kimliğini hiçbir SDK RevenueCat'e kaydetmediği için sanal para
  ayarlaması **404** alır; o API müşteriyi kendisi oluşturmuyor. Bu endpoint'in
  doğru çalıştığının işareti, hata değil. Gerçek cihazda `bootstrap()` önce
  `loadOfferings()` çağırıp müşteriyi oluşturduğu için sorun çıkmıyor
  ([PurchaseManager.swift:156](RoastMyGallery/Services/Purchases/PurchaseManager.swift#L156)
  — o iki satırın sırası yük taşıyor, değiştirme).
- **Yerel StoreKit satın alması gem vermiyor** — RevenueCat'in sunucu tarafı
  grant'i tetiklenmiyor. Kutlama ekranı "+10 gems" der ama bakiye artmaz.
  Beklenen davranış, hata değil.
- ~~**Worker kaynağı repoda yok**~~ — **çözüldü.** Kaynak artık `site/` altında.
  Düzenle → `cd site && npx wrangler deploy`. Geri alma: `npx wrangler rollback`.
  - ⚠️ **`wrangler init --from-dash roastmygallery` ÇALIŞMAZ** — sessizce boş bir
    "Hello World" şablonu üretir, çünkü site bir Workers **Static Assets**
    dağıtımı; içerik script'te değil asset'lerde ve `--from-dash` asset
    indirmiyor. O şablonu deploy etmek **siteyi silerdi**.
  - ⚠️ **Deploy tüm asset manifest'ini değiştirir** — `site/public/` içinde
    olmayan dosya canlıdan silinir. Şu an 8 dosya var; silmeden önce say.
  - Cloudflare kimlik bilgileri `~/.wrangler`'da değil,
    `~/Library/Preferences/.wrangler/config/default.toml`'da.
- **SourceKit indeksi bu projede sık bozuluyor** — editörde "Cannot find 'Theme'
  in scope" / "No such module 'UIKit'" gibi hatalar görürsen genelde gerçek
  değil. Xcode'da bir kez build edince geçiyor.
