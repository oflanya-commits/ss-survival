-- Bu dosya, survival ve ARC modlarının bütün oynanış ayarlarını merkezi olarak yönetir.
-- Aşağıdaki yorumlar her tablonun ve alanın ne işe yaradığını hızlıca anlamak için eklendi.

Config = {}

-- [CRAFT TARİFLERİ]
-- Her kayıt, crafting menüsünde gösterilen tek bir üretim tarifidir.
-- header: Menüde görünen başlık
-- txt: Oyuncuya gösterilen gereksinim özeti
-- icon: Menü ikonu
-- category: Menüde hangi sekmede/listede gruplanacağını belirler
-- params.event: Tarif seçildiğinde tetiklenecek client event'i
-- params.args.item: Üretilecek item adı
-- params.args.amount: Üretilecek adet
-- params.args.label: İlerleme/notify tarafında kullanılacak okunabilir isim
-- params.args.requirements: Gerekli item ve adet listesi
Config.CraftRecipes = {
    {
        header = "9mm Mermi Paketi",
        txt = "Gereksinim: 10 Metal Parçası, 5 Barut",
        icon = "fas fa-box-open",
        category = "ammo",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "ammo-9",
                amount = 30,
                label = "9mm Mermi Paketi",
                requirements = {
                    { item = "metalscrap", amount = 10 },
                    { item = "gunpowder", amount = 5 }
                }
            }
        }
    },
    {
        header = "IFAK (Gelişmiş İlk Yardım)",
        txt = "Gereksinim: 3 Bandaj, 1 Yanık Kremi",
        icon = "fas fa-medkit",
        category = "health",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "ifaks",
                amount = 1,
                label = "IFAK",
                requirements = {
                    { item = "bandage", amount = 3 },
                    { item = "burncream", amount = 1 }
                }
            }
        }
    },
    {
        header = "Tamir Kiti (Repairkit)",
        txt = "Gereksinim: 15 Hurda Metal, 10 Kauçuk",
        icon = "fas fa-tools",
        category = "material",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "repairkit",
                amount = 1,
                label = "Repairkit",
                requirements = {
                    { item = "scrapmetal", amount = 15 },
                    { item = "rubber", amount = 10 }
                }
            }
        }
    },
    {
        header = "Hafif Zırh",
        txt = "Gereksinim: 12 Kumaş, 6 Hurda Metal, 4 Kauçuk",
        icon = "fas fa-shield-alt",
        category = "health",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "armor",
                amount = 1,
                label = "Hafif Zırh",
                requirements = {
                    { item = "cloth", amount = 12 },
                    { item = "scrapmetal", amount = 6 },
                    { item = "rubber", amount = 4 }
                }
            }
        }
    },
    {
        header = "Tabanca",
        txt = "Gereksinim: 15 Hurda Metal, 1 Tabanca Blueprint",
        icon = "fas fa-tools",
        category = "weapon",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "weapon_pistol",
                amount = 1,
                label = "Tabanca",
                requirements = {
                    { item = "scrapmetal", amount = 15 },
                    { item = "pistol_blueprint", amount = 1 }
                }
            }
        }
    },
    {
        header = "Combat Pistol",
        txt = "Gereksinim: 18 Hurda Metal, 8 Metal Parçası, 1 Combat Pistol Blueprint",
        icon = "fas fa-tools",
        category = "weapon",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "weapon_combatpistol",
                amount = 1,
                label = "Combat Pistol",
                requirements = {
                    { item = "scrapmetal", amount = 18 },
                    { item = "metalscrap", amount = 8 },
                    { item = "combatpistol_blueprint", amount = 1 }
                }
            }
        }
    },
    {
        header = "Micro SMG",
        txt = "Gereksinim: 24 Hurda Metal, 10 Metal Parçası, 6 Kauçuk, 1 Micro SMG Blueprint",
        icon = "fas fa-tools",
        category = "weapon",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "weapon_microsmg",
                amount = 1,
                label = "Micro SMG",
                requirements = {
                    { item = "scrapmetal", amount = 24 },
                    { item = "metalscrap", amount = 10 },
                    { item = "rubber", amount = 6 },
                    { item = "microsmg_blueprint", amount = 1 }
                }
            }
        }
    },
    {
        header = "SMG",
        txt = "Gereksinim: 28 Hurda Metal, 12 Metal Parçası, 8 Kauçuk, 1 SMG Blueprint",
        icon = "fas fa-tools",
        category = "weapon",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "weapon_smg",
                amount = 1,
                label = "SMG",
                requirements = {
                    { item = "scrapmetal", amount = 28 },
                    { item = "metalscrap", amount = 12 },
                    { item = "rubber", amount = 8 },
                    { item = "smg_blueprint", amount = 1 }
                }
            }
        }
    },
    {
        header = "Carbine Rifle",
        txt = "Gereksinim: 34 Hurda Metal, 16 Metal Parçası, 8 Barut, 1 Carbine Rifle Blueprint",
        icon = "fas fa-tools",
        category = "weapon",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "weapon_carbinerifle",
                amount = 1,
                label = "Carbine Rifle",
                requirements = {
                    { item = "scrapmetal", amount = 34 },
                    { item = "metalscrap", amount = 16 },
                    { item = "gunpowder", amount = 8 },
                    { item = "carbinerifle_blueprint", amount = 1 }
                }
            }
        }
    },
    {
        header = "Assault Rifle",
        txt = "Gereksinim: 40 Hurda Metal, 18 Metal Parçası, 10 Barut, 1 Assault Rifle Blueprint",
        icon = "fas fa-tools",
        category = "weapon",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "weapon_assaultrifle",
                amount = 1,
                label = "Assault Rifle",
                requirements = {
                    { item = "scrapmetal", amount = 40 },
                    { item = "metalscrap", amount = 18 },
                    { item = "gunpowder", amount = 10 },
                    { item = "assaultrifle_blueprint", amount = 1 }
                }
            }
        }
    },
    {
        header = "ARC Barricade Kit",
        txt = "Gereksinim: 20 Hurda Metal, 10 Metal Parçası, 4 Kauçuk",
        icon = "fas fa-shield-alt",
        category = "material",
        params = {
            event = "gs-survival:client:craftItem",
            args = {
                item = "arc_barricade_kit",
                amount = 1,
                label = "ARC Barricade Kit",
                requirements = {
                    { item = "scrapmetal", amount = 20 },
                    { item = "metalscrap", amount = 10 },
                    { item = "rubber", amount = 4 }
                }
            }
        }
    }
}

-- [BÖLÜM (STAGE) YAPILANDIRMASI]
-- Her stage, klasik survival modunda oynanabilecek ayrı bir senaryoyu temsil eder.
-- label: Menüde görünen stage adı
-- center: Sınır kontrolü ve genel odak noktası için merkezin koordinatı
-- multiplier: Zorluk/ölçek çarpanı; NPC doğruluğu ve benzeri hesaplarda kullanılır
-- spawnPoints: Düşmanların doğabileceği pozisyonlar
-- Waves: Dalga listesi
--   npcCount: O dalgada toplam spawn olacak NPC sayısı
--   pedModel: NPC modeli
--   isDogWave: Bu dalganın köpek dalgası olup olmadığını belirtir
--   label: Dalga etiketi
--   weapon: NPC'ye verilecek silah
Config.Stages = {
    [1] = {
        label = "Gecekondu Baskını - Kolay",
        center = vector3(-127.15, -1584.77, 32.29), 
        multiplier = 1.0,
        spawnPoints = {
            -- Merkezin çevresindeki dar sokaklar ve çatılar/köşeler
            vector3(-81.26, -1613.18, 31.49), -- Kuzeybatı sokak arası
            -- vector3(-139.59, -1632.87, 32.55), -- Kuzeydoğu garaj arkası
            -- vector3(-71.32, -1586.99, 30.12), -- Güneydoğu çöp konteyner yanı
            -- vector3(-166.87, -1594.41, 34.36), -- Güneybatı ev arkası
            -- vector3(-125.10, -1470.80, 33.60), -- Kuzey girişi
        },
        Waves = {
            [1] = { npcCount = 1, pedModel = `g_m_y_famdnf_01`, isDogWave = false, label = "Sokak Çetesi", weapon = "weapon_bat" },
            -- [2] = { npcCount = 4, pedModel = `g_m_y_famca_01`, isDogWave = false, label = "Sokak Çetesi", weapon = "weapon_pistol" },
        }
    },
    [2] = {
        label = "Liman Operasyonu - Orta",
        center = vector3(1235.43, -3003.26, 9.32), 
        multiplier = 1.2,
        spawnPoints = {
            -- Konteynır araları ve vinç altları
            vector3(1228.03, -3068.66, 5.9), -- Konteynır bloğu A
            vector3(1222.08, -2906.67, 5.87), -- Vinç altı açık alan
            vector3(1174.97, -2933.73, 5.9), -- Kuzey Liman girişi
            -- vector3(1146.36, -3002.13, 5.9), -- Depo önü
            -- vector3(1164.24, -3054.69, 5.9), -- Rıhtım ucu
        },
        Waves = {
            [1] = { npcCount = 1, pedModel = `s_m_y_blackops_01`, isDogWave = false, label = "Liman Güvenliği", weapon = "weapon_smg" },
            [2] = { npcCount = 1, pedModel = `s_m_y_blackops_01`, isDogWave = false, label = "Liman Güvenliği", weapon = "weapon_smg" },
        }
    },
        [3] = {
        label = "Jilet Fadıl - Zor",
        center = vector3(1387.87, 1147.03, 114.33), 
        multiplier = 1.6,
        spawnPoints = {
            vector3(1318.72, 1106.94, 105.97), 
            vector3(1418.45, 1177.02, 114.33), 
            vector3(1432.47, 1121.08, 114.25), 
            vector3(1369.02, 1098.44, 113.86), 
            vector3(1473.22, 1130.18, 114.33), 
        },
        Waves = {
            [1] = { npcCount = 3, pedModel = `g_m_m_chicold_01`, isDogWave = false, label = "Koruma", weapon = "weapon_pistol" },
            [2] = { npcCount = 4, pedModel = `g_m_m_chicold_01`, isDogWave = false, label = "Koruma", weapon = "weapon_combatpistol" },
            [3] = { npcCount = 3, pedModel = `g_m_m_chicold_01`, isDogWave = false, label = "Koruma", weapon = "weapon_smg" },
            [4] = { npcCount = 6, pedModel = `g_m_m_chicold_01`, isDogWave = false, label = "Koruma", weapon = "weapon_assaultrifle" },
        }
    },
}
-- [BAŞLANGIÇ NPC AYARLARI]
-- Lobi/başlangıç menüsünü açan sabit NPC'nin modelini, konumunu ve etiketini tanımlar.
Config.Npc = {
    Model = `a_m_m_og_boss_01`,
    Coords = vector4(-122.5, -1500.2, 33.5, 120.0), 
    Label = "Operasyon Menüsü"
}

-- Oyun modu seçim menüsünde listelenecek modlar.
-- id: Sistem içi benzersiz mod anahtarı
-- label: Oyuncuya gösterilecek isim
-- description: Menü açıklaması
Config.GameModes = {
    classic = {
        id = "classic",
        label = "Klasik Hayatta Kalma",
        description = "Dalgalar halinde gelen düşmanlara karşı hayatta kal."
    },
    arc_pvp = {
        id = "arc_pvp",
        label = "ARC Baskını",
        description = "Ganimet kasalarını topla, rakiplerini ele ve bölgeden sağ çık."
    }
}

Config.Survival = {
    -- Oyuncunun survival oturum durumunu metadata üzerinde takip etmek için kullanılan anahtar adları.
    Metadata = {
        activeFlag = "in_survival",
        modeKey = "survival_mode",
        weapon = "survival_weapon",
        armor = "survival_armor",
        level = "survival_level"
    },
    -- Survival başlarken alınan envanteri geçici olarak saklayan yedek stash ayarları.
    -- Prefix: Her oyuncu için oluşturulan stash ID'sinin ön eki
    -- Label: Envanter arayüzünde görünen depo adı
    -- Slots/Weight: ox_inventory kapasite ayarları
    BackupStash = {
        Prefix = "surv_backup_",
        Label = "Survival Yedek",
        Slots = 50,
        Weight = 100000
    }
}

-- [SAVAŞ VE ZORLUK AYARLARI]
-- Klasik survival modunun savaş akışını belirleyen temel ayarlar.
-- WaveWaitTime: Dalgalar arası bekleme süresi
-- NpcAccuracy: NPC doğruluk taban değeri
-- BoundaryDistance: Oyuncunun stage merkezinden ne kadar uzaklaşabileceği
-- BoundaryWarningBufferPct: Sınır uyarısının toplam sınırın yüzde kaç kala başlayacağı
-- MinBoundaryWarningBuffer: Yüzde hesabı düşük kalsa bile minimum uyarı tamponu
-- BoundaryWarningCooldownMs: Sınır uyarısı tekrar gösterilmeden önce beklenecek süre
-- SpawnProtectionMs: Oyuncu spawn olduktan sonra verilen geçici koruma süresi
-- LootTime: NPC loot açma süresi
-- DefaultWeapon/DefaultAmmo/DefaultAmmoAmount: Oyuncuya varsayılan verilen başlangıç loadout'u
Config.Combat = {
    WaveWaitTime = 16, 
    NpcAccuracy = 25, 
    BoundaryDistance = 90.0, -- Oyuncunun merkezden ne kadar uzaklaşabileceği
    BoundaryWarningBufferPct = 0.2,
    MinBoundaryWarningBuffer = 20.0,
    BoundaryWarningCooldownMs = 15000,
    SpawnProtectionMs = 5000,
    LootTime = 10000, 
    DefaultWeapon = "WEAPON_PISTOL",
    DefaultAmmo = "ammo-9",
    DefaultAmmoAmount = 100
}

-- [LOOT AYARLARI]
-- Klasik survival NPC loot havuzu.
-- item: Düşebilecek item adı
-- min/max: Tek düşüşte verilebilecek minimum ve maksimum adet
-- chance: Yüzdelik düşme ihtimali
-- type: İç sınıflandırma/analiz etiketi
-- minWave: Bu item'in hangi dalgadan sonra çıkabileceği
-- keepOnExit: Mod bitince oyuncuda kalıp kalmayacağı
Config.LootTable = {
    -- Combat (Para ve Mermi)
    { item = "money", min = 100, max = 500, chance = 50, type = "combat", keepOnExit = true },
    { item = "weapon_assaultrifle", chance = 5, min = 1, max = 1, keepOnExit = true },
    { item = "black_money", min = 50, max = 200, chance = 20, type = "combat", keepOnExit = true },
    { item = "ammo-9", min = 10, max = 30, chance = 100, type = "combat", keepOnExit = true },
    
    -- Craft Malzemeleri (Common)
    { item = "scrapmetal", min = 2, max = 5, chance = 25, type = "craft", keepOnExit = true },
    { item = "metalscrap", min = 2, max = 4, chance = 20, type = "craft", keepOnExit = true },
    { item = "rubber", min = 1, max = 3, chance = 18, type = "craft", keepOnExit = true },
    { item = "cloth", min = 2, max = 4, chance = 22, type = "craft", keepOnExit = true },
    
    -- Survival (Food/Med)
    { item = "water_bottle", min = 1, max = 1, chance = 15, type = "survival", keepOnExit = true },
    { item = "tosti", min = 1, max = 1, chance = 12, type = "survival", keepOnExit = true },
    { item = "bandage", min = 1, max = 1, chance = 10, type = "survival", keepOnExit = true },
    { item = "burncream", min = 1, max = 1, chance = 5, type = "survival", keepOnExit = true },
    
    -- Nadir Malzemeler
    { item = "electronics", min = 1, max = 1, chance = 5, type = "rare", minWave = 3, keepOnExit = true }, 
    { item = "pistol_blueprint", min = 1, max = 1, chance = 15, type = "rare", minWave = 3, keepOnExit = true },
    { item = "cryptostick", min = 1, max = 1, chance = 1, type = "rare", minWave = 4, keepOnExit = true },
    { item = "gunpowder", min = 1, max = 3, chance = 15, type = "craft", keepOnExit = true },
    { item = "medkit", min = 1, max = 1, chance = 5, type = "survival", keepOnExit = true },
    { item = "ifaks", min = 1, max = 1, chance = 3, type = "survival", keepOnExit = true }
}

Config.ArcPvP = {
    -- ARC baskını sırasında oyuncunun metadata'sında tutulan durum anahtarları.
    Metadata = {
        activeFlag = "in_arc_pvp",
        modeKey = "arc_mode"
    },
    -- true ise oyuncu kendi kişisel envanterini ARC oturumuna da taşıyabilir.
    AllowPersonalInventory = true,
    -- Oyuncu bağlantı kestiğinde ne yapılacağını belirler: rollback / death / rejoin.
    DisconnectPolicy = "rejoin", --rollback - death - rejoin
    -- true yapılırsa oyuncunun baskına girmeden önce loadout çantasını hazırlamış olması zorunlu olur.
    RequirePreparedLoadout = false,
    -- Arka arkaya baskın başlatma denemeleri arasındaki debounce süresi.
    StartDebounceMs = 6000,
    -- true ise deployment verisi server tarafında daha katı doğrulanır.
    StrictDeploymentValidation = true,
    -- Oyuncuya özel ARC stash ID'leri oluşturulurken kullanılan önekler.
    MainStashPrefix = "arc_main_",
    LoadoutStashPrefix = "arc_loadout_",
    BackupStashPrefix = "arc_backup_",
    -- ARC stash arayüzlerinde görünen adlar.
    MainStashLabel = "ARC Ana Depo",
    LoadoutStashLabel = "ARC Baskın Çantası",
    -- Kalıcı ana deponun kapasite ayarları.
    MainStashSlots = 80,
    MainStashWeight = 200000,
    -- Baskın loadout çantasının kapasite ayarları.
    LoadoutStashSlots = 24,
    LoadoutStashWeight = 75000,
    -- Kişisel eşya yedeği için kullanılan geçici emanet deposu ayarları.
    BackupStashLabel = "ARC Geçici Emanet",
    BackupStashSlots = 50,
    BackupStashWeight = 100000,
    -- Dünya üzerinde spawn edilen loot objelerinin modelleri.
    ChestModel = `prop_box_wood02a_pu`,
    DropModel = `prop_drop_crate_01_set2`,
    -- Yerleştirilebilir ARC barikat item'inin davranış ayarları.
    -- Item: Kullanılacak item adı
    -- Label: UI/notify etiketi
    -- Model: Yerleştirilecek obje modeli
    -- PlaceDistance: Oyuncudan ne kadar öne preview atılacağı
    -- InteractDistance: Barikata yaklaşma/etkileşim mesafesi
    -- PreviewAlpha: Preview objesinin saydamlık değeri
    -- PlacementDurationMs: Yerleştirme süresi
    -- RotationStep: Her döndürmede kaç derece çevrileceği
    -- MaxPerPlayer: Bir oyuncunun aynı baskında koyabileceği maksimum barikat
    -- MaxPerRaid: Tüm baskın boyunca izin verilen toplam barikat
    -- MinSpacing: İki barikat arasında bırakılması gereken minimum mesafe
    BarricadeKit = {
        Item = "arc_barricade_kit",
        Label = "ARC Barricade Kit",
        Model = `prop_mp_barrier_02b`,
        PlaceDistance = 2.2,
        InteractDistance = 4.0,
        PreviewAlpha = 160,
        PlacementDurationMs = 2500,
        RotationStep = 3.0,
        MaxPerPlayer = 2,
        MaxPerRaid = 16,
        MinSpacing = 2.5
    },
    -- ARC baskınlarında sınır/yeniden giriş/oturum eşleştirme davranışları.
    -- BoundaryPadding: Deployment merkezine göre ekstra izinli hareket alanı
    -- SpawnProtectionMs: Deployment sonrası geçici koruma
    -- SpawnClearRadius: Spawn çevresinde loot/engeller temizlenirken baz alınan yarıçap
    -- MinInsertionLootDistance: Spawn noktasına çok yakın loot çıkmasını engeller
    -- RaidDurationSeconds: Tek baskının toplam süresi
    -- MaxPlayersPerRaid: Bir aktif ARC oturumundaki toplam oyuncu sınırı
    -- ReuseMinimumRemainingSeconds: Var olan bir baskını tekrar kullanmak için gereken minimum kalan süre
    -- RejoinPolicy: Yeniden bağlanan oyuncunun aynı oturuma dönme kuralı
    -- LateJoinCutoffSeconds: Bu süre geçince yeni squad baskına alınmaz
    -- AllowJoinAfterExtractionUnlocked: Extraction açıldıktan sonra yeni takım kabul edilip edilmeyeceği
    -- DenyJoinIfSquadPreviouslyEliminated: O baskında elenmiş takımın tekrar girişinin engellenmesi
    -- MinimumRemainingSecondsForBackfill: Backfill için gerekli minimum kalan süre
    -- SessionReuseStrategy: Uygun oturum seçilirken hangi stratejinin kullanılacağı
    -- DeploymentNotifyDelay: Deployment ekranı ile oyun içi bildirim arasındaki gecikme
    BoundaryPadding = 35.0,
    SpawnProtectionMs = 8000,
    SpawnClearRadius = 125.0,
    MinInsertionLootDistance = 18.0,
    RaidDurationSeconds = 1800,
    MaxPlayersPerRaid = 40,
    ReuseMinimumRemainingSeconds = 1080,
    RejoinPolicy = "same_session_only", -- disabled / same_session_only
    LateJoinCutoffSeconds = 720, -- after this many elapsed seconds, new squads are no longer allowed to join
    AllowJoinAfterExtractionUnlocked = false, -- if false, extraction unlock closes the raid to fresh squads
    DenyJoinIfSquadPreviouslyEliminated = true, -- deny re-entry to the same active raid after a squad member dies there
    MinimumRemainingSecondsForBackfill = 1080, -- active raid must have at least this much time left to accept a new squad
    SessionReuseStrategy = "most_remaining", -- most_remaining / least_population
    DeploymentNotifyDelay = 1200,
    -- Extraction fazının çalışma kuralları.
    -- UnlockMode: Çıkışın nasıl açılacağı (manuel çağrı, süreye bağlı, her zaman açık, son faz)
    -- UnlockAfterSeconds/LastPhaseUnlockSeconds: Çıkış kilidi açılma zamanları
    -- CallDelay: Helikopter/çıkış çağrısından sonra aktif olmaya kadar geçecek süre
    -- ReadyWindowSeconds: Biniş/çıkış için tanınan pencere
    -- ManualDepartureCountdownSeconds: Manuel kalkış başlatılınca geri sayım
    -- ZoneRadius: Çıkış alanının yarıçapı
    -- RequireFullTeam/AllowSoloExtract/AllowPartialTeamExtract: Takım bütünlüğü kuralları
    -- CancelIfZoneEmpty: Alan boş kalırsa extraction'ın iptal edilmesi
    -- BoardingInterruptOnLeave: Alan terk edilince binişin bozulması
    -- AutoFailIfNoExtract: Süre bitince çıkılamadıysa baskının başarısız sayılması
    -- ManualDepartureEnabled/AutoDepartureOnTimeout: Kalkışın nasıl tetikleneceği
    -- NotifyAllPlayers: Extraction bildirimlerinin herkese gidip gitmeyeceği
    -- SpawnHelicopter/UseHelicopterScene/HelicopterModel/HelicopterHeight: Sinematik helikopter ayarları
    -- CleanupDelay: Extraction sonrası temizleme gecikmesi
    -- Zones: Kullanılabilecek çıkış noktaları (label/coords/heading)
    Extraction = {
        Enabled = true,
        Debug = false,
        UnlockMode = "always_available", -- manual_call / time_unlock / always_available / last_phase
        UnlockAfterSeconds = 600,
        LastPhaseUnlockSeconds = 240,
        CallDelay = 45,
        ReadyWindowSeconds = 90,
        ManualDepartureCountdownSeconds = 20,
        ZoneRadius = 12.0,
        RequireFullTeam = false,
        AllowSoloExtract = true,
        AllowPartialTeamExtract = true,
        CancelIfZoneEmpty = false,
        BoardingInterruptOnLeave = true,
        AutoFailIfNoExtract = true,
        ManualDepartureEnabled = true,
        AutoDepartureOnTimeout = true,
        NotifyAllPlayers = true,
        SpawnHelicopter = true,
        UseHelicopterScene = true,
        HelicopterModel = "frogger",
        HelicopterHeight = 80.0,
        CleanupDelay = 10000,
        Zones = {
            { label = "North Ridge", coords = vector3(-706.17, 499.34, 109.29), heading = 236.0 },
            { label = "Industrial Lift", coords = vector3(929.16, -1013.25, 38.55), heading = 271.0 },
            { label = "South Extraction", coords = vector3(1232.22, -3157.42, 5.53), heading = 179.0 }
        }
    },
    -- ARC baskını başında oyuncuya verilen varsayılan loadout.
    -- Weapon: Başlangıç silahı
    -- Ammo/AmmoAmount: Verilecek mermi tipi ve miktarı
    -- Armor: Başlangıç zırhı
    -- Items: Ek başlangıç item listesi
    Loadout = {
        Weapon = "weapon_pistol",
        Ammo = "ammo-9",
        AmmoAmount = 90,
        Armor = 0,
        Items = {
            { item = "bandage", count = 2 },
            { item = "water_bottle", count = 1 }
        }
    },
    -- ARC arena havuzu; server uygun bir arena seçerken bu listeyi kullanır.
    -- center: Baskın merkezin koordinatı
    -- multiplier: Zorluk/ödül ölçeği
    -- lootNodeCount: Rastgele seçilecek standart loot noktası sayısı
    -- highValueNodeCount: Yüksek değerli loot noktası sayısı
    Arenas = {
        [1] = {
            label = "Tarama Protokolü I",
            center = vector3(215.56, -933.21, 30.69),
            multiplier = 1.0,
            lootNodeCount = 8,
            highValueNodeCount = 1
        },
        [2] = {
            label = "Tarama Protokolü II",
            center = vector3(215.56, -933.21, 30.69),
            multiplier = 1.2,
            lootNodeCount = 10,
            highValueNodeCount = 2
        },
        [3] = {
            label = "Tarama Protokolü III",
            center = vector3(215.56, -933.21, 30.69),
            multiplier = 1.6,
            lootNodeCount = 12,
            highValueNodeCount = 3
        }
    },
    -- Deployment bölgeleri, oyuncuların map üzerinde konuşlandırıldığı baskın alanlarıdır.
    -- lootRegion: O bölgenin hangi loot kalitesi tablosunu kullanacağını belirtir
    -- insertionPoints: Takımların bırakılabileceği giriş noktaları
    -- extractionPoint: Bölgenin önerilen/ana çıkış koordinatı
    -- lootNodes: Bölge içine dağılacak loot noktaları
    --   coords: Kasanın/sandığın doğacağı konum
    --   type: chest veya drop; hangi model/görselin kullanılacağını etkiler
    --   rollCount: Bu node açıldığında kaç kez loot roll yapılacağı
    --   label: Etkileşim etiket adı
    DeploymentZones = {
        [1] = {
            label = "Güney Los Santos Taraması",
            lootRegion = "blue",
            center = vector3(126.58, -1943.47, 20.8),
            insertionPoints = {
                vector3(283.15, -1732.99, 29.4),
                vector3(-218.16, -1635.07, 33.55),
                vector3(200.55, -1659.87, 29.8)
            },
            extractionPoint = vector3(184.44, -1968.53, 20.12),
            lootNodes = {
                { coords = vector3(62.84, -1905.62, 21.67), type = "chest", rollCount = 1, label = "Terkedilmiş Daire" },
                { coords = vector3(87.52, -1958.73, 20.75), type = "chest", rollCount = 1, label = "Arka Sokak Kasası" },
                { coords = vector3(116.81, -1970.2, 20.75), type = "drop", rollCount = 2, label = "Sinyal Sandığı" },
                { coords = vector3(138.64, -1921.65, 21.38), type = "chest", rollCount = 1, label = "Çatı Kutusu" },
                { coords = vector3(168.07, -1870.58, 24.39), type = "chest", rollCount = 1, label = "Dükkan Arkası" },
                { coords = vector3(201.23, -1896.19, 24.33), type = "chest", rollCount = 1, label = "Panel Kutusu" },
                { coords = vector3(214.6, -1949.8, 20.14), type = "drop", rollCount = 2, label = "Yüksek Değerli Sandık" },
                { coords = vector3(153.17, -2004.52, 18.33), type = "chest", rollCount = 1, label = "Avlu Sandığı" },
                { coords = vector3(74.26, -1974.28, 20.75), type = "chest", rollCount = 1, label = "Alt Geçit Kutusu" },
                { coords = vector3(132.48, -2009.15, 18.86), type = "drop", rollCount = 2, label = "Mahalle Sinyali" },
                { coords = vector3(181.06, -1929.52, 21.38), type = "chest", rollCount = 1, label = "Sokak Arası Kasası" },
                { coords = vector3(223.71, -1976.84, 20.14), type = "chest", rollCount = 1, label = "Bariyer Kutusu" }
            }
        },
        [2] = {
            label = "La Mesa Sanayi Hattı",
            lootRegion = "blue",
            center = vector3(847.92, -1033.41, 28.19),
            insertionPoints = {
                vector3(731.35, -1403.89, 26.52),
                vector3(723.54, -755.88, 25.37),
                vector3(1127.28, -1299.94, 34.73)
            },
            extractionPoint = vector3(929.16, -1013.25, 38.55),
            lootNodes = {
                { coords = vector3(797.44, -1013.26, 26.22), type = "chest", rollCount = 1, label = "Depo Kasası" },
                { coords = vector3(822.6, -1064.23, 27.83), type = "chest", rollCount = 1, label = "Forklift Sandığı" },
                { coords = vector3(850.87, -1026.77, 28.0), type = "drop", rollCount = 2, label = "Konveyör Sandığı" },
                { coords = vector3(875.47, -989.51, 30.69), type = "chest", rollCount = 1, label = "Çatı Paneli" },
                { coords = vector3(911.37, -1059.89, 32.82), type = "chest", rollCount = 1, label = "Makine Sandığı" },
                { coords = vector3(938.64, -1031.28, 35.97), type = "drop", rollCount = 2, label = "Veri Kasası" },
                { coords = vector3(903.78, -985.35, 39.27), type = "chest", rollCount = 1, label = "Üst Raf Deposu" },
                { coords = vector3(842.67, -982.26, 26.5), type = "chest", rollCount = 1, label = "Servis Kutusu" },
                { coords = vector3(785.12, -1046.73, 26.21), type = "chest", rollCount = 1, label = "Yedek Parça Kasası" },
                { coords = vector3(832.94, -1004.52, 26.27), type = "drop", rollCount = 2, label = "Hat Sonu Sandığı" },
                { coords = vector3(918.16, -1011.84, 35.89), type = "chest", rollCount = 1, label = "Yük Köprüsü Kutusu" },
                { coords = vector3(956.74, -1047.91, 35.36), type = "chest", rollCount = 1, label = "Depo Girişi Kasası" }
            }
        },
        [3] = {
            label = "Liman Çıkış Koridoru",
            lootRegion = "green",
            center = vector3(1214.73, -2998.91, 5.87),
            insertionPoints = {
                vector3(624.97, -2970.39, 6.05),
                vector3(766.59, -3288.67, 6.1),
                vector3(884.63, -2872.22, 19.02)
            },
            extractionPoint = vector3(1232.22, -3157.42, 5.53),
            lootNodes = {
                { coords = vector3(1176.54, -2988.29, 5.9), type = "chest", rollCount = 1, label = "Konteyner Kasası" },
                { coords = vector3(1198.85, -3044.85, 5.91), type = "chest", rollCount = 1, label = "İskele Kutusu" },
                { coords = vector3(1230.67, -3003.9, 9.31), type = "drop", rollCount = 2, label = "Yüzer Sandık" },
                { coords = vector3(1261.76, -3059.85, 5.91), type = "chest", rollCount = 1, label = "Vinç Sandığı" },
                { coords = vector3(1281.43, -2965.55, 5.91), type = "chest", rollCount = 1, label = "Rıhtım Deposu" },
                { coords = vector3(1221.08, -2914.92, 5.87), type = "chest", rollCount = 1, label = "Açık Kasa" },
                { coords = vector3(1166.53, -2933.32, 5.9), type = "drop", rollCount = 2, label = "Liman Sinyali" },
                { coords = vector3(1206.13, -3112.47, 5.54), type = "chest", rollCount = 1, label = "Gümrük Kutusu" },
                { coords = vector3(1142.28, -2998.36, 5.9), type = "chest", rollCount = 1, label = "Kıyı Deposu" },
                { coords = vector3(1244.83, -3078.34, 5.91), type = "drop", rollCount = 2, label = "Transit Sinyali" },
                { coords = vector3(1274.17, -3017.42, 8.11), type = "chest", rollCount = 1, label = "Üst Güverte Kutusu" },
                { coords = vector3(1184.66, -3090.51, 5.54), type = "chest", rollCount = 1, label = "Kargo Çıkışı Kasası" }
            }
        },
        [4] = {
            label = "Vinewood Geçidi",
            lootRegion = "green",
            center = vector3(-596.85, 541.23, 107.75),
            insertionPoints = {
                vector3(-644.64, 675.86, 150.39),
                vector3(-347.54, 625.16, 171.36),
                vector3(-500.68, 428.54, 101.88)
            },
            extractionPoint = vector3(-706.17, 499.34, 109.29),
            lootNodes = {
                { coords = vector3(-653.09, 560.84, 110.49), type = "chest", rollCount = 1, label = "Teras Kasası" },
                { coords = vector3(-620.91, 507.82, 108.99), type = "chest", rollCount = 1, label = "Giriş Kutusu" },
                { coords = vector3(-574.78, 520.67, 106.19), type = "drop", rollCount = 2, label = "Yamaç Sandığı" },
                { coords = vector3(-533.24, 477.95, 103.19), type = "chest", rollCount = 1, label = "Garaj Deposu" },
                { coords = vector3(-664.98, 471.02, 114.14), type = "chest", rollCount = 1, label = "Çatışma Kasası" },
                { coords = vector3(-717.8, 491.25, 109.38), type = "drop", rollCount = 2, label = "Sırt Hattı Sandığı" },
                { coords = vector3(-690.12, 551.19, 113.93), type = "chest", rollCount = 1, label = "Villa Paneli" },
                { coords = vector3(-559.87, 591.11, 108.95), type = "chest", rollCount = 1, label = "Yan Bahçe Kutusu" },
                { coords = vector3(-611.54, 561.47, 110.01), type = "chest", rollCount = 1, label = "Merdiven Kasası" },
                { coords = vector3(-580.74, 484.42, 108.61), type = "drop", rollCount = 2, label = "Yamaç Sinyali" },
                { coords = vector3(-702.63, 538.67, 110.27), type = "chest", rollCount = 1, label = "Siper Kutusu" },
                { coords = vector3(-521.28, 545.88, 112.23), type = "chest", rollCount = 1, label = "Villa Terası Deposu" }
            }
        },
        [5] = {
            label = "Sandy Shores Hattı",
            lootRegion = "red",
            center = vector3(1889.41, 3717.08, 32.74),
            insertionPoints = {
                vector3(892.51, 3610.2, 32.92),
                vector3(1238.5, 3376.04, 55.05),
                vector3(2437.87, 4067.54, 38.06)
            },
            extractionPoint = vector3(1964.12, 3821.91, 32.21),
            lootNodes = {
                { coords = vector3(1848.31, 3690.02, 34.27), type = "chest", rollCount = 1, label = "Karavan Kasası" },
                { coords = vector3(1875.4, 3736.56, 32.97), type = "chest", rollCount = 1, label = "Benzinlik Kutusu" },
                { coords = vector3(1915.13, 3729.08, 32.73), type = "drop", rollCount = 2, label = "Tozlu Sandık" },
                { coords = vector3(1948.84, 3759.41, 32.22), type = "chest", rollCount = 1, label = "Atölye Deposu" },
                { coords = vector3(1966.61, 3686.62, 32.8), type = "chest", rollCount = 1, label = "Depo Kasası" },
                { coords = vector3(1817.42, 3678.57, 34.28), type = "drop", rollCount = 2, label = "Kurak Sinyal" },
                { coords = vector3(1851.63, 3773.94, 33.06), type = "chest", rollCount = 1, label = "Arka Sokak Kutusu" },
                { coords = vector3(1986.44, 3783.62, 32.18), type = "chest", rollCount = 1, label = "Hurda Kasası" },
                { coords = vector3(1836.25, 3723.67, 33.27), type = "chest", rollCount = 1, label = "Motel Arkası Kasası" },
                { coords = vector3(1902.84, 3689.51, 32.87), type = "drop", rollCount = 2, label = "Kurye Sandığı" },
                { coords = vector3(1972.35, 3742.08, 32.19), type = "chest", rollCount = 1, label = "Lastik Deposu" },
                { coords = vector3(1860.77, 3810.54, 33.07), type = "chest", rollCount = 1, label = "Yol Kenarı Kutusu" }
            }
        },
        [6] = {
            label = "Grapeseed Çiftlikleri",
            lootRegion = "red",
            center = vector3(2448.73, 4958.8, 46.81),
            insertionPoints = {
                vector3(2863.72, 4901.64, 63.44),
                vector3(2192.33, 5598.07, 53.74),
                vector3(1951.82, 4650.4, 40.65)
            },
            extractionPoint = vector3(2530.73, 4685.14, 33.84),
            lootNodes = {
                { coords = vector3(2413.57, 4991.69, 46.23), type = "chest", rollCount = 1, label = "Ahır Kasası" },
                { coords = vector3(2452.04, 4972.57, 51.56), type = "drop", rollCount = 2, label = "Silo Sandığı" },
                { coords = vector3(2477.26, 4957.55, 45.12), type = "chest", rollCount = 1, label = "Tarla Sandığı" },
                { coords = vector3(2503.47, 5003.04, 44.9), type = "chest", rollCount = 1, label = "Çit Arkası Kasa" },
                { coords = vector3(2447.02, 5026.56, 46.13), type = "chest", rollCount = 1, label = "Kamyon Deposu" },
                { coords = vector3(2368.89, 4884.42, 41.81), type = "drop", rollCount = 2, label = "Röle Sinyali" },
                { coords = vector3(2543.72, 4675.55, 33.76), type = "chest", rollCount = 1, label = "Değirmen Kutusu" },
                { coords = vector3(2462.18, 4892.41, 36.53), type = "chest", rollCount = 1, label = "Gübre Deposu" },
                { coords = vector3(2397.54, 4970.84, 45.87), type = "chest", rollCount = 1, label = "Sulama Kutusu" },
                { coords = vector3(2490.91, 4931.37, 44.69), type = "drop", rollCount = 2, label = "Tarla Sinyali" },
                { coords = vector3(2521.63, 5017.92, 45.11), type = "chest", rollCount = 1, label = "Samanlık Kasası" },
                { coords = vector3(2428.37, 4916.56, 41.35), type = "chest", rollCount = 1, label = "Kanal Deposu" }
            }
        },
        [7] = {
            label = "Paleto Kereste Yolu",
            lootRegion = "yellow",
            center = vector3(-559.18, 5368.93, 70.23),
            insertionPoints = {
                vector3(-488.1, 4924.23, 147.01),
                vector3(-1001.06, 5157.04, 128.55),
                vector3(-754.48, 5589.12, 41.65)
            },
            extractionPoint = vector3(-456.85, 6012.4, 31.49),
            lootNodes = {
                { coords = vector3(-547.92, 5317.69, 73.6), type = "chest", rollCount = 1, label = "Odunluk Kasası" },
                { coords = vector3(-578.17, 5264.31, 70.47), type = "chest", rollCount = 1, label = "Kesim Kasası" },
                { coords = vector3(-604.83, 5243.74, 71.53), type = "drop", rollCount = 2, label = "Kereste Sandığı" },
                { coords = vector3(-510.08, 5269.16, 79.61), type = "chest", rollCount = 1, label = "Kule Deposu" },
                { coords = vector3(-457.72, 5378.55, 80.36), type = "chest", rollCount = 1, label = "Tepe Kasası" },
                { coords = vector3(-430.16, 5988.6, 31.71), type = "drop", rollCount = 2, label = "Kuzey Sinyali" },
                { coords = vector3(-615.79, 5296.88, 70.21), type = "chest", rollCount = 1, label = "Ağaç Kesim Kutusu" },
                { coords = vector3(-489.24, 5285.54, 80.61), type = "chest", rollCount = 1, label = "Kamp Deposu" },
                { coords = vector3(-561.31, 5288.14, 73.1), type = "chest", rollCount = 1, label = "Yığın Kasası" },
                { coords = vector3(-528.76, 5351.83, 75.27), type = "drop", rollCount = 2, label = "Tomruk Sinyali" },
                { coords = vector3(-603.47, 5332.56, 70.24), type = "chest", rollCount = 1, label = "Kesim Hattı Kutusu" },
                { coords = vector3(-465.89, 5339.72, 86.17), type = "chest", rollCount = 1, label = "Seyir Noktası Kasası" }
            }
        },
        [8] = {
            label = "Chumash Kıyısı",
            lootRegion = "yellow",
            center = vector3(-3186.61, 1294.44, 14.58),
            insertionPoints = {
                vector3(-3416.81, 967.15, 8.35),
                vector3(-2994.57, 770.09, 26.99),
                vector3(-2804.12, 1423.24, 100.93)
            },
            extractionPoint = vector3(-3026.87, 77.53, 11.61),
            lootNodes = {
                { coords = vector3(-3204.09, 1224.46, 10.04), type = "chest", rollCount = 1, label = "Sahil Kasası" },
                { coords = vector3(-3173.44, 1274.42, 14.56), type = "chest", rollCount = 1, label = "Yol Kenarı Kutusu" },
                { coords = vector3(-3142.96, 1333.74, 18.43), type = "drop", rollCount = 2, label = "Yamaç Sandığı" },
                { coords = vector3(-3097.7, 1211.35, 20.31), type = "chest", rollCount = 1, label = "Tepelik Deposu" },
                { coords = vector3(-3028.33, 82.36, 11.61), type = "chest", rollCount = 1, label = "Otoyol Kutusu" },
                { coords = vector3(-2969.42, 389.74, 15.04), type = "drop", rollCount = 2, label = "Kıyı Sinyali" },
                { coords = vector3(-3216.21, 1112.93, 10.01), type = "chest", rollCount = 1, label = "İskele Sandığı" },
                { coords = vector3(-3087.27, 658.47, 11.67), type = "chest", rollCount = 1, label = "Tünel Deposu" },
                { coords = vector3(-3234.52, 1259.83, 6.79), type = "chest", rollCount = 1, label = "Sahil İnişi Kasası" },
                { coords = vector3(-3121.66, 1287.74, 19.21), type = "drop", rollCount = 2, label = "Kayalık Sandık" },
                { coords = vector3(-3041.17, 165.25, 14.12), type = "chest", rollCount = 1, label = "Otoyol Bariyeri Kutusu" },
                { coords = vector3(-3003.42, 470.66, 15.26), type = "chest", rollCount = 1, label = "Kıyı Şeridi Deposu" }
            }
        }
    },
    -- Bölge renklerine göre ayrılmış loot tabloları.
    -- label: UI/map üzerinde görünen renk bölgesi adı
    -- lootTable: O renk bölgesine ait item havuzu
    LootRegions = {
        blue = {
            label = "Mavi Bölge",
            lootTable = {
                { item = "ammo-9", min = 15, max = 35, chance = 100 },
                { item = "metalscrap", min = 2, max = 4, chance = 52 },
                { item = "scrapmetal", min = 1, max = 3, chance = 34 },
                { item = "cloth", min = 2, max = 4, chance = 32 },
                { item = "bandage", min = 1, max = 1, chance = 48 },
                { item = "water_bottle", min = 1, max = 1, chance = 35 },
                { item = "money", min = 100, max = 350, chance = 55 }
            }
        },
        green = {
            label = "Yeşil Bölge",
            lootTable = {
                { item = "ammo-9", min = 20, max = 45, chance = 100 },
                { item = "metalscrap", min = 2, max = 5, chance = 64 },
                { item = "scrapmetal", min = 2, max = 4, chance = 52 },
                { item = "rubber", min = 1, max = 3, chance = 32 },
                { item = "cloth", min = 3, max = 6, chance = 42 },
                { item = "gunpowder", min = 1, max = 2, chance = 16 },
                { item = "bandage", min = 1, max = 2, chance = 60 },
                { item = "water_bottle", min = 1, max = 2, chance = 45 },
                { item = "burncream", min = 1, max = 1, chance = 24 },
                { item = "money", min = 200, max = 600, chance = 65 }
            }
        },
        red = {
            label = "Kırmızı Bölge",
            lootTable = {
                { item = "ammo-9", min = 25, max = 60, chance = 100 },
                { item = "metalscrap", min = 3, max = 6, chance = 76 },
                { item = "scrapmetal", min = 3, max = 6, chance = 68 },
                { item = "rubber", min = 2, max = 4, chance = 48 },
                { item = "cloth", min = 4, max = 7, chance = 44 },
                { item = "gunpowder", min = 2, max = 4, chance = 30 },
                { item = "bandage", min = 1, max = 2, chance = 70 },
                { item = "water_bottle", min = 1, max = 2, chance = 50 },
                { item = "burncream", min = 1, max = 2, chance = 30 },
                { item = "pistol_blueprint", min = 1, max = 1, chance = 3 },
                { item = "combatpistol_blueprint", min = 1, max = 1, chance = 2 },
                { item = "microsmg_blueprint", min = 1, max = 1, chance = 1 },
                { item = "smg_blueprint", min = 1, max = 1, chance = 1 },
                { item = "carbinerifle_blueprint", min = 1, max = 1, chance = 1 },
                { item = "assaultrifle_blueprint", min = 1, max = 1, chance = 1 },
                { item = "weapon_pistol", min = 1, max = 1, chance = 8 },
                { item = "money", min = 350, max = 900, chance = 75 }
            }
        },
        yellow = {
            label = "Sarı Bölge",
            lootTable = {
                { item = "ammo-9", min = 35, max = 80, chance = 100 },
                { item = "metalscrap", min = 4, max = 8, chance = 84 },
                { item = "scrapmetal", min = 4, max = 8, chance = 80 },
                { item = "rubber", min = 2, max = 5, chance = 58 },
                { item = "cloth", min = 5, max = 9, chance = 58 },
                { item = "gunpowder", min = 3, max = 5, chance = 44 },
                { item = "bandage", min = 1, max = 3, chance = 80 },
                { item = "water_bottle", min = 1, max = 2, chance = 55 },
                { item = "burncream", min = 1, max = 2, chance = 40 },
                { item = "pistol_blueprint", min = 1, max = 1, chance = 10 },
                { item = "combatpistol_blueprint", min = 1, max = 1, chance = 8 },
                { item = "microsmg_blueprint", min = 1, max = 1, chance = 6 },
                { item = "smg_blueprint", min = 1, max = 1, chance = 5 },
                { item = "carbinerifle_blueprint", min = 1, max = 1, chance = 3 },
                { item = "assaultrifle_blueprint", min = 1, max = 1, chance = 2 },
                { item = "weapon_pistol", min = 1, max = 1, chance = 12 },
                { item = "money", min = 500, max = 1400, chance = 85 }
            }
        }
    },
    -- Bölgesel loot tanımı yoksa fallback olarak kullanılan genel ARC loot havuzu.
    LootTable = {
        { item = "ammo-9", min = 20, max = 60, chance = 100 },
        { item = "metalscrap", min = 2, max = 5, chance = 58 },
        { item = "scrapmetal", min = 2, max = 5, chance = 48 },
        { item = "rubber", min = 1, max = 3, chance = 30 },
        { item = "cloth", min = 2, max = 5, chance = 36 },
        { item = "gunpowder", min = 1, max = 3, chance = 20 },
        { item = "bandage", min = 1, max = 2, chance = 60 },
        { item = "burncream", min = 1, max = 2, chance = 25 },
        { item = "water_bottle", min = 1, max = 2, chance = 40 },
        { item = "pistol_blueprint", min = 1, max = 1, chance = 2 },
        { item = "combatpistol_blueprint", min = 1, max = 1, chance = 1 },
        { item = "weapon_pistol", min = 1, max = 1, chance = 10 },
        { item = "money", min = 250, max = 1000, chance = 75 }
    }
}
-- [MARKET GELİŞTİRMELERİ]
-- Marketten satın alınabilen kalıcı geliştirmeler.
-- price: Satın alma maliyeti
-- value: Metadata'ya yazılacak gerçek değer
-- label: Menüde görünen isim
-- metadataName: Oyuncu metadata'sında güncellenecek alan
-- sqlColumn: Kalıcılık için veritabanında güncellenecek kolon
-- ammoType/ammoAmount: Silah paketleri için yanında verilecek mühimmat
Config.Upgrades = {
    ["armor"] = {
        price = 50000,
        value = 100,
        label = "Çelik Yelek (100 Zırh)",
        metadataName = "survival_armor",
        sqlColumn = "survival_armor"
    },
    ["weapon_microsmg"] = {
        price = 100000,
        value = "WEAPON_MICROSMG",
        label = "Uzi Paketi",
        metadataName = "survival_weapon",
        sqlColumn = "survival_weapon",
        ammoType = "ammo-45",
        ammoAmount = 1000
    },
    ["weapon_assaultrifle"] = {
        price = 100000,
        value = "WEAPON_ASSAULTRIFLE",
        label = "AK-47 Paketi",
        metadataName = "survival_weapon",
        sqlColumn = "survival_weapon",
        ammoType = "ammo-rifle2",
        ammoAmount = 1000
    },
}
