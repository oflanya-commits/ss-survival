# GS-Survival FiveM Script — Kapsamlı Kod Analizi

> **Analiz Tarihi:** 2026-03-27  
> **Analiz Dili:** Türkçe  
> **Kapsam:** `client.lua`, `server.lua`, `config.lua`, `fxmanifest.lua`

---

## 1. Genel Yapı ve Organizasyon

### 1.1 Dosya Yapısı

Script dört ana dosyadan oluşmaktadır:

| Dosya | Satır Sayısı | Görev |
|-------|-------------|-------|
| `fxmanifest.lua` | 19 | Kaynak tanımı ve bağımlılık bildirimi |
| `config.lua` | 209 | Tüm oyun parametrelerinin merkezi konfigürasyonu |
| `client.lua` | 894 | Client-side oyun mantığı |
| `server.lua` | 711 | Server-side veri yönetimi ve güvenlik |

### 1.2 Modüller ve Bölümler

**client.lua:**
- Market sistemi (satın alma ve UI açma)
- Reconnect/güvenli bölge kontrolü
- İlişki grupları (relationship groups)
- Başlangıç NPC'si ve ox_target entegrasyonu
- Temizlik (cleanup) eventi
- Ölüm ve spectate sistemi
- Trafik ve yoğunluk kontrolü
- Alan temizliği thread'i
- Mesafe ve sınır kontrolü
- Craft menüsü
- NPC silme eventi
- Dalga yönetimi ve sayım geri sayımı
- Survival başlatma
- NPC kurulum ve blip sistemi
- Envanter kilitleme
- Dünya temizliği
- Spectate sistemi
- Loot stash açma
- Menü sistemi (ana menü, stage menüsü, davet menüsü)
- Lobi yönetimi (lider/üye)
- Survival başlatma tetikleyicisi

**server.lua:**
- Global değişkenler ve loot tablosu oluşturma
- Davet gönderme
- Yere atılan eşya kontrolü (ox_inventory hook)
- Bucket temizliği
- Survival başlatma (envanter yedekleme, kit dağıtma)
- Dalga spawn sistemi
- Craft malzeme kontrolü callback'i
- Lobi yönetimi (onay, listeleme, dağıtma, ayrılma)
- Crafting tamamlama
- Market satın alma
- Oyun bitiş / geri yükleme sistemi
- Oyun düşme (playerDropped) yönetimi
- Reconnect yedek kontrolü callback'i
- NPC loot stash sistemi
- Loot durum kontrolü ve iptal
- Yakındaki oyuncular callback'i

### 1.3 Global Değişkenler

```lua
-- client.lua
local QBCore = exports['qb-core']:GetCoreObject()
local currentWave, isSurvivalActive, myBucket = 0, false, 0
local activeStageId = 1
local spawnedPeds, invitedPlayers = {}, {}
local waitingForWave, countdown = false, 0
local notifiedDeath = false
local isEnding = false
local activeSurvivalPlayers = {}
local waveTimer = 0           -- hiç kullanılmıyor
local isLobbyLeader = false   -- hiç kullanılmıyor
local inLobbyAsMember = false -- kısmen kullanılıyor
local lobbyLeaderId = nil

-- server.lua
local groupSizes, groupMembers, playerBackups = {}, {}, {}
local createdStashes, beingLooted = {}, {}
local lobbyStage = {}
local activeLobbies = {}
local lootItemSet = {}
local finishingPlayers = {}
```

**Değerlendirme:** Global değişkenler makul biçimde `local` olarak tutulmuş. Ancak `waveTimer` ve `isLobbyLeader` hiç kullanılmadığı hâlde yer işgal etmektedir. `createdStashes` tablosu server.lua'da oluşturulmuş ama asla doldurulmamaktadır.

### 1.4 Thread Yönetimi

Script toplamda **5 kalıcı thread** (`Citizen.CreateThread`) kullanmaktadır:

1. İlişki grubu kurulum thread'i (tek seferlik)
2. Başlangıç NPC oluşturma thread'i (tek seferlik)
3. Ölüm kontrolü thread'i (1 saniyelik uyku)
4. Trafik yoğunluğu sıfırlama thread'i (isSurvivalActive aktifken `Wait(0)`)
5. Alan temizliği thread'i (5 saniyelik uyku)
6. Mesafe/sınır kontrolü thread'i (500 ms–2000 ms uyku)

Thread 4 (`Wait(0)` döngüsü) survival aktifken her karede çalışmaktadır; bu FiveM best practice'lerine uygun bir tasarımdır.

---

## 2. İşlevsellik ve Mekanikler

### 2.1 Survival Başlatma Akışı

```
Client: startFinal → Server: startSurvival
    → Envanter yedekle (stash + RAM)
    → Envanteri temizle
    → Kit ver (silah, mermi)
    → Zırh ver (metadata'dan)
    → Routing bucket ata
    → Oyuncuyu koordinata ışınla
    → Client: initSurvival
        → Ekranı karart
        → NPC'yi gizle
        → Oyuncuyu konumlandır
        → Dalga geri sayımını başlat
```

### 2.2 Dalga (Wave) Sistemi

Her dalga şu adımları izler:
1. `StartWaveCountdown()` → `WaveWaitTime` kadar bekler
2. `TriggerServerEvent('gs-survival:server:spawnWave', ...)` → Server'da NPC'ler doğar
3. Her spawn noktası için `cfg.npcCount` kadar NPC oluşturulur, bucket'a yerleştirilir
4. `TriggerClientEvent('gs-survival:client:setupNpc', ...)` → Client blip ve target ekler
5. Client loop NPC sayımını takip eder; tümü ölünce sonraki dalgaya geçer veya loot aşaması başlar

### 2.3 Loot Sistemi

NPC'yi öldüren oyuncu "Üstünü Ara" target'ını görür → progress bar → server stash oluşturur → client stash inventoryyi açar. Dalga numarası loot şansını %5 artırır.

### 2.4 Craft Sistemi

Komut ya da menü aracılığıyla açılır. Sunucu malzeme kontrolü yapar, animasyon çalınır, ardından sunucu tekrar kontrol edip eşyayı teslim eder. **Çift doğrulama** mevcut; bu güvenlik açısından iyidir.

### 2.5 Market Sistemi

Config.Upgrades tablosuna bakarak zırh/silah geliştirmesi satar. Metadata'ya ve SQL'e (oxmysql) yazar.

### 2.6 Spectate Sistemi

Ölü oyuncu `activeSurvivalPlayers` listesindeki hayatta kalan oyuncuları kamera ile izler. Sol/sağ ok tuşuyla hedef değiştirilir.

### 2.7 Reconnect Koruma

`in_survival` metadata bayrağı ve `ox_inventory` stash sistemi sayesinde oyuncu yeniden bağlandığında envanteri geri yüklenir.

### 2.8 Lobi Yönetimi

Lider oyuncu diğer oyuncuları davet eder → onaylandığında `activeLobbies[leaderId]` tablosuna eklenir → survival başlatıldığında tüm lobi üyeleri başlatılır.

---

## 3. Kod Kalitesi ve İyi Uygulamalar

### 3.1 Okunabilirlik

- Bölüm başlıkları `-- [BÖLÜM ADI]` formatında tutulmuş; bu iyi bir pratiktir.
- Fonksiyon isimleri açıklayıcıdır (`StartWaveCountdown`, `RestorePlayer`, `CleanBucketEntities`).
- `RestorePlayer` fonksiyonu `finishSurvival` handler'ı içinde iç içe (nested) tanımlanmış; okunabilirliği düşürür, ayrı bir dosya düzeyinde fonksiyon olmalıdır.

### 3.2 Yorum Yeterliliği

Yorumlar genelde yeterli ve Türkçedir. Ancak bazı kritik güvenlik kontrolleri için açıklama eksiktir. Örneğin `beingLooted` tablosunun neden `npcNetId`'ye göre indexlendiği açıklanmamış.

### 3.3 Değişken İsimlendirme

- `peps` → `participants` veya `players` daha anlamlı olurdu.
- `sId` hem `stageId` hem de `stashId` kısaltması olarak farklı scope'larda kullanılmış; kafa karıştırıcı.
- `bId` → `bucketId` tam yazılması önerilir.

### 3.4 Kod Tekrarları (Duplication)

`finishSurvival` handler'ında `isLastPerson` kontrolü ve ardından gelen `CleanBucketEntities` + `groupMembers` + `lobbyStage` temizliği hem `status == true` hem `status == false` dalında tekrar ediyor:

```lua
-- Bu blok iki yerde tekrarlanıyor (satır ~476-482 ve ~510-530)
local isLastPerson = false
if not groupMembers[bucketId] or #groupMembers[bucketId] <= 1 then 
    CleanBucketEntities(bucketId)
    isLastPerson = true
end
-- ...
if isLastPerson then
    lobbyStage[bucketId] = nil
    createdStashes = {}
    beingLooted = {}
end
```

**Refactoring önerisi:** Bu mantık ayrı bir `CleanupBucket(bucketId)` fonksiyonuna taşınmalıdır.

### 3.5 FiveM Best Practices Uyumu

| Kural | Durum |
|-------|-------|
| `Wait(0)` ile CPU yoğun döngüler | ✅ Sadece gerekli durumda |
| `Citizen.CreateThread` yerine `CreateThread` kullanımı | ⚠️ Satır 517'de tutarsız |
| Entity existence kontrolleri | ✅ Çoğu yerde yapılmış |
| Routing bucket temizliği | ✅ Mevcut |
| Event spam koruması (`finishingPlayers`) | ✅ Mevcut |

---

## 4. Potansiyel Hatalar ve Bug'lar

### 4.1 [KRİTİK] Sözdizimi Hatası — client.lua:202

```lua
-- HATALI (iki statement arasında ayraç yok):
if teleportLeeway < 10 then teleportLeeway = teleportLeeway + 1 dist = 0 end

-- DOĞRU:
if teleportLeeway < 10 then teleportLeeway = teleportLeeway + 1; dist = 0 end
```

Bu satır, Lua'nın bazı implementasyonlarında hata verebilir veya beklenmedik davranışa yol açabilir.

### 4.2 [KRİTİK] deleteNPC Yanlış Broadcast — server.lua:668

```lua
-- HATALI: -1 tüm oyunculara gönderir (bucket dışındakilere de)
TriggerClientEvent('gs-survival:client:deleteNPC', -1, npcNetId)

-- DOĞRU: Sadece bucket üyelerine gönder
if groupMembers[bId] then
    for _, pId in pairs(groupMembers[bId]) do
        TriggerClientEvent('gs-survival:client:deleteNPC', pId, npcNetId)
    end
end
```

### 4.3 [ORTA] isSpectating Kapsam Sorunu — client.lua

`isSpectating` değişkeni satır 582'de `local spectateIndex, isSpectating, spectateCam = 1, false, nil` olarak tanımlanmıştır; ancak satır 533'teki `stopEverything` event handler'ında `isSpectating = false` olarak kullanılmaktadır. Bu assignment, `stopEverything` event handler'ı Lua script'inin o noktasında tanımlı olmayan bir scope'a erişmeye çalışır. Lua'da değişkenler lexical scope'a tabidir; ancak bu iki blok aynı chunk'ta olduğu için fiilen çalışabilir. Yine de kodun başında tüm local değişkenlerin tanımlanması önerilir.

### 4.4 [ORTA] Config'de weapon_assaultrifle Loot Şansı — config.lua:157

```lua
{ item = "weapon_assaultrifle", chance = 100, min = 1, max = 1, keepOnExit = true },
```

`chance = 100` her öldürülen NPC'den her zaman bir AK-47 düşeceği anlamına gelir. Bu büyük ihtimalle bir test kalıntısıdır ve oyun ekonomisini bozar.

### 4.5 [ORTA] RegisterServerEvent + AddEventHandler Çifti — server.lua:323-324

```lua
-- Gereksiz tekrar; sadece RegisterNetEvent + AddEventHandler veya
-- sadece RegisterNetEvent (FiveM'de server event'ler için) yeterlidir
RegisterServerEvent('gs-survival:server:buyUpgrade')
AddEventHandler('gs-survival:server:buyUpgrade', function(data) ... end)

-- DOĞRU:
RegisterNetEvent('gs-survival:server:buyUpgrade', function(data) ... end)
```

### 4.6 [ORTA] waveTimer ve isLobbyLeader Kullanılmıyor — client.lua

```lua
local waveTimer = 0          -- hiç kullanılmıyor, temizlenmeli
local isLobbyLeader = false  -- hiç kullanılmıyor, temizlenmeli
```

### 4.7 [ORTA] createdStashes Dolduruluyor mu? — server.lua

`createdStashes = {}` temizleme satırları mevcut ancak `createdStashes` tablosuna hiçbir yerde veri eklenmemektedir. Bu muhtemelen tamamlanmamış bir özelliğin kalıntısıdır.

### 4.8 [DÜŞÜK] Loot Şans Hesabında Taşma

```lua
local luckMultiplier = 1.0 + (wave * 0.05)
if roll <= (loot.chance * luckMultiplier) then
```

Yüksek dalga sayılarında (örn. dalga 20'de `luckMultiplier = 2.0`), `chance = 100` olan öğelerin etkin şansı 200 olur. `math.min(loot.chance * luckMultiplier, 100)` ile sınırlandırılmalıdır.

### 4.9 [DÜŞÜK] Boundary Check Sırasında Nil Referans Riski

```lua
local stageData = Config.Stages[activeStageId]
if stageData and stageData.center then
    local dist = #(coords - stageData.center)
```

`activeStageId` geçersiz bir değere sahipse `stageData` nil olur ve kontrol sessizce atlanır. Bu kabul edilebilir ama loglanmalıdır.

### 4.10 [DÜŞÜK] Server `Wait` Kullanımı

```lua
Wait(250)  -- server.lua:113
Wait(600)  -- server.lua:427
Wait(1000) -- server.lua:596
```

Server-side `Wait` kullanımı FiveM'de desteklenir ancak bazı durumlarda öngörülemeyen davranışlara yol açabilir. Genel olarak `Citizen.SetTimeout` veya callback zinciri tercih edilmelidir.

---

## 5. Güvenlik ve Exploit Riskleri

### 5.1 [KRİTİK] Client-Side Stage Seçimi

```lua
-- client.lua (satır 888-893)
RegisterNetEvent('gs-survival:client:startFinal', function(data)
    local selectedStage = data and data.stageId or 1
    activeStageId = selectedStage
    TriggerServerEvent('gs-survival:server:startSurvival', invitedPlayers, selectedStage)
    invitedPlayers = {}
end)
```

Kötü niyetli bir oyuncu `TriggerServerEvent('gs-survival:server:startSurvival', {}, 999)` çağrısı yaparak herhangi bir stage'i başlatmaya çalışabilir. Server tarafında `selectedStage`'in gerçekten var olup olmadığı ve oyuncunun o stage'e yetkisi olup olmadığı **doğrulanmıyor**.

**Düzeltme:**
```lua
-- server.lua'da startSurvival handler başına ekle:
if not Config.Stages[stageId] then
    TriggerClientEvent('QBCore:Functions:Notify', src, "Geçersiz operasyon bölgesi!", "error")
    return
end
local playerLevel = Player.PlayerData.metadata["survival_level"] or 1
if stageId > playerLevel then
    TriggerClientEvent('QBCore:Functions:Notify', src, "Bu bölge için yeterli seviyeniz yok!", "error")
    return
end
```

### 5.2 [KRİTİK] Market Fiyat Manipülasyonu

```lua
-- client.lua (satır 20-32)
params = { event = "gs-survival:client:marketBridge", args = { type = "armor", value = 100, price = 50000 } }
```

Client, `price` parametresini server'a göndermektedir. Kötü niyetli bir oyuncu event'i direkt çağırarak farklı bir `price` değeri gönderebilir. Server tarafında fiyat **Config.Upgrades**'dan alındığı için bu risk azaltılmış olmakla birlikte yine de `data.price` parametresinin server'a iletilmesi gereksizdir.

**Düzeltme:**
```lua
-- server.lua buyUpgrade handler'ında price'ı config'den alın, client'tan değil:
local price = upgradeData.price  -- data.price yerine Config.Upgrades'dan al (mevcut, iyi)
-- data.price alanı artık ignore ediliyor, doğru — ancak client'tan kaldırılması temizlik sağlar
```

### 5.3 [YÜKSEK] Craft Verisi Client'tan Geliyor

```lua
-- client.lua (satır 362)
TriggerServerEvent('gs-survival:server:finishCrafting', data)
```

`data` nesnesi; `item`, `amount`, `requirements` gibi kritik alanları içermektedir ve tamamı client'tan gelmektedir. Kötü niyetli bir oyuncu kendi `data` objesini oluşturabilir. Server'da `requirements` kontrol edilmektedir; ancak `item` ve `amount` doğrudan kullanılmaktadır:

```lua
Player.Functions.AddItem(data.item, data.amount)
```

`data.item`'ın Config.CraftRecipes içinde gerçekten tanımlı olup olmadığı kontrol edilmemektedir.

**Düzeltme:**
```lua
-- server.lua finishCrafting'de item ve amount'ı config'den doğrula:
local validRecipe = nil
for _, recipe in ipairs(Config.CraftRecipes) do
    if recipe.params.args.item == data.item and recipe.params.args.amount == data.amount then
        validRecipe = recipe.params.args
        break
    end
end
if not validRecipe then
    TriggerClientEvent('QBCore:Functions:Notify', src, "Geçersiz üretim talebi!", "error")
    return
end
-- validRecipe'den requirements kullan, data.requirements yerine
```

### 5.4 [ORTA] Davet Sistemi Kötüye Kullanımı

```lua
-- server.lua (satır 21)
RegisterNetEvent('gs-survival:server:sendInvite', function(tId) 
    TriggerClientEvent('gs-survival:client:receiveInvite', tId, source) 
end)
```

Bir oyuncu istediği oyuncuya sürekli davet gönderebilir (spam). Rate limiting mekanizması yoktur.

### 5.5 [ORTA] NPC Spawn Sunucu Doğrulaması

`spawnWave` event'i server tarafında tanımlı, bu güzel. Ancak kötü niyetli bir client `gs-survival:server:spawnWave` event'ini direkt çağırabilir ve `bId` ile `wave` değerlerini manipüle edebilir:

```lua
RegisterNetEvent('gs-survival:server:spawnWave', function(bId, wave, stageId)
    -- bId'nin gerçekten bu oyuncuya ait olup olmadığı doğrulanmıyor
```

**Düzeltme:**
```lua
local src = source
local playerBucket = GetPlayerRoutingBucket(src)
if playerBucket ~= bId then return end
```

### 5.6 [DÜŞÜK] Loot Stash'inin Başkasına Açılması

`createNpcStash` sonunda stash ID client'a gönderilmektedir. Bu stash ID tahmin edilemez (`surv_` + netId + random(1111,9999)) ancak teorik olarak başka bir oyuncu aynı stash ID'sini kullanarak içeriğe erişebilir (ox_inventory stash erişimi istemci üzerinden yapılıyorsa).

---

## 6. İyileştirme ve Optimizasyon Önerileri

### 6.1 Performans

**Thread konsolidasyonu:** Ölüm kontrolü, trafik sıfırlama ve mesafe kontrolü thread'leri tek bir thread'de birleştirilebilir:

```lua
Citizen.CreateThread(function()
    while true do
        local sleep = 1000
        if isSurvivalActive then
            sleep = 500
            SetVehicleDensityMultiplierThisFrame(0.0)
            -- ... diğer density ayarları
            -- ölüm kontrolü
            -- mesafe kontrolü
        end
        Wait(sleep)
    end
end)
```

**Alan temizliği:** `ClearAreaOfPeds` ve `ClearAreaOfVehicles` her 5 saniyede çağrılmaktadır. `spawnedPeds` tablosu mevcut olduğu için bu fonksiyonların ayrıca çağrılması gereksiz olabilir.

### 6.2 NPC Sağlık Hesabı

```lua
local newHealth = math.floor(200 * stageMult)
SetEntityMaxHealth(npc, newHealth)
SetEntityHealth(npc, newHealth)
```

GTA V'te `SetEntityMaxHealth` entity'nin taban sağlığını, `SetEntityHealth` ise mevcut sağlığını ayarlar. `SetEntityHealth` her zaman `SetEntityMaxHealth`'ten *sonra* çağrılmalıdır; bu doğru yapılmaktadır.

### 6.3 Kayıt Edilmemiş Değişkenlerin Temizlenmesi

```lua
-- Kaldırılması gereken kullanılmayan değişkenler:
local waveTimer = 0       -- hiç kullanılmıyor
local isLobbyLeader = false -- hiç kullanılmıyor
```

### 6.4 Dalga Geri Sayımı İyileştirmesi

`StartWaveCountdown` her dalga geçişinde yeni bir thread oluşturmaktadır. Bu thread'in önceki örneklerinin temizlendiğinden emin olmak için `isSurvivalActive` flag kontrolü zaten mevcuttur; ancak notifiedDeath durumunda thread'in durması kontrol edilmelidir.

### 6.5 SQL Injection Riski — Sınırlı

```lua
local query = string.format('UPDATE players SET %s = ? WHERE citizenid = ?', sqlCol)
```

`sqlCol` değeri `Config.Upgrades`'dan geldiği için kullanıcı kontrolünde değildir; ancak bu pattern genel olarak risklidir. Sabit bir whitelist kullanmak daha güvenlidir:

```lua
local allowedColumns = { survival_armor = true, survival_weapon = true }
if not allowedColumns[sqlCol] then return end
```

### 6.6 Yeni Özellik Önerileri

- **Anti-cheat:** Oyuncu konumunun server-side teleport tespiti
- **Leaderboard:** Tamamlanan dalga sayısı ve elde edilen loot istatistikleri
- **Dinamik zorluk:** Grup büyüklüğüne göre NPC sayısı otomatik ölçekleme
- **Ses efektleri:** Dalga bildirimleri için ses çalma
- **Boss dalgası:** Config'e `isBossWave` bayrağı ekleyerek özel boss NPC'leri

---

## 7. Uyumluluk ve Bağımlılıklar

### 7.1 Bağımlılık Listesi

| Bağımlılık | Kullanım Yeri | Zorunlu |
|-----------|--------------|---------|
| `qb-core` | Oyuncu verisi, callback, notify | ✅ Evet |
| `ox_inventory` | Envanter yönetimi, stash | ✅ Evet |
| `ox_target` | NPC etkileşimi | ✅ Evet |
| `ox_lib` | Notify ve progress bar | ✅ Evet |
| `qb-menu` | Tüm UI menüleri | ✅ Evet |
| `oxmysql` | SQL güncellemeleri | ✅ Evet |

### 7.2 fxmanifest Eksiklikleri

```lua
-- fxmanifest.lua'da tanımlanmamış ancak kullanılan bağımlılıklar:
-- ox_inventory, ox_target, ox_lib, qb-menu için 'dependency' bildirimi yok
```

**Düzeltme:**
```lua
dependencies {
    'qb-core',
    'ox_inventory',
    'ox_target',
    'ox_lib',
    'qb-menu',
}
```

### 7.3 Config Entegrasyonu

Config dosyası shared script olarak yüklenmiştir (`shared_scripts`) ve hem client hem server tarafında erişilebilmektedir. Bu doğru bir yaklaşımdır. Ancak Config'in client tarafında okunabilmesi, bazı değerlerin (ör. loot şansları) client tarafından görülebileceği anlamına gelir.

### 7.4 `Config.Combat.DefaultItems` Eksikliği

Server.lua satır 116'da `Config.Combat.DefaultItems` kontrol edilmektedir, ancak bu anahtar config.lua'da tanımlı değildir. `nil` kontrolü yapıldığından crash olmaz; ancak bu özellik işlevsizdir.

---

## 8. Özet ve Genel Değerlendirme

### 8.1 Güçlü Yönler

- ✅ Routing bucket sistemi doğru kullanılmış (izolasyon sağlıyor)
- ✅ Envanter yedekleme sistemi kapsamlı (stash + RAM + metadata flag)
- ✅ Reconnect koruması mevcut ve işlevsel
- ✅ Çift sunucu doğrulaması bazı kritik işlemlerde uygulanmış (crafting)
- ✅ Loot sistem dinamik (dalga bazlı şans artışı)
- ✅ Lobi sistemi temel işlevleri kapsıyor
- ✅ Spectate sistemi çalışır durumda
- ✅ Event spam koruması mevcut (`finishingPlayers` tablosu)

### 8.2 Zayıf Yönler

- ❌ Stage seçimi client'ta doğrulanmıyor (exploit riski yüksek)
- ❌ Craft item/amount server'da config'den doğrulanmıyor
- ❌ deleteNPC tüm oyunculara broadcast yapıyor (-1)
- ❌ Sözdizimi hatası (client.lua satır 202)
- ❌ config.lua'da test kalıntısı loot değerleri (weapon_assaultrifle %100 şans)
- ❌ fxmanifest'te bağımlılık bildirimleri eksik
- ❌ Davet spam koruması yok

### 8.3 Puanlama

| Kriter | Puan (1-10) |
|--------|------------|
| Genel Yapı | 7 |
| İşlevsellik | 7 |
| Kod Kalitesi | 6 |
| Hata Yönetimi | 6 |
| Güvenlik | 4 |
| Performans | 7 |
| Uyumluluk | 6 |
| **GENEL ORTALAMA** | **6.1 / 10** |

Script, temel survival oyun döngüsünü başarıyla implement etmiş, QBCore ve ox ekosistemleriyle entegrasyonu sağlamıştır. Ancak güvenlik açıkları (özellikle stage yetkilendirme ve crafting doğrulama eksiklikleri) ve bazı kritik bug'lar (syntax hatası, broadcast sorunu) üretim ortamına alınmadan önce düzeltilmelidir.
