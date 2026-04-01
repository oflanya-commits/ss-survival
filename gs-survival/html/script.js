'use strict';

const STRINGS = {
    app: {
        title: 'Operasyon Arayüzü',
        subtitle: 'Tüm operasyon akışlarını buradan yönet.',
        breadcrumb: 'Operasyon Menüsü / Ana Ekran'
    },
    badge: {
        solo: 'SOLO',
        team: 'TAKIM',
        leader: 'LİDER',
        waiting: 'BEKLİYOR',
        ready: 'HAZIR',
        locked: 'KİLİTLİ',
        active: 'AKTİF'
    },
    notifyTitle: {
        info: 'Bilgilendirme',
        success: 'Başarılı',
        error: 'Hata',
        warning: 'Uyarı',
        primary: 'ARC Bildirimi'
    },
    progress: {
        title: 'Operasyon Sürüyor',
        label: 'Lütfen bekle...',
        cancel: 'ESC ile iptal edebilirsin',
        locked: 'İptal devre dışı'
    },
    banner: {
        label: 'ARC TAHLİYE',
        title: 'Lobiye Dönülüyor'
    },
    barricade: {
        title: 'ARC Barricade Kit'
    },
    empty: {
        market: 'Satın alınabilir güçlendirme bulunamadı.',
        craft: 'Görüntülenecek tarif bulunamadı.',
        stages: 'Seçilebilir stage bulunamadı.',
        invite: 'Davet edilebilecek oyuncu bulunamadı.',
        lobbies: 'Şu anda görüntülenecek aktif lobi yok.',
        members: 'Takımda görüntülenecek oyuncu kalmadı.',
        locker: 'Bu kategoride eşya bulunamadı.'
    },
    craftCategories: {
        all: 'Tümü',
        ammo: 'Mermi',
        weapon: 'Silah',
        health: 'Sağlık',
        material: 'Malzeme',
        misc: 'Diğer'
    },
    lockerCategories: {
        all: 'Tümü',
        weapon: 'Silah',
        ammo: 'Mermi',
        medical: 'Medikal',
        food: 'Gıda',
        utility: 'Ekipman',
        misc: 'Diğer'
    },
    teamStatus: {
        self: { badge: 'SEN', text: 'Sen' },
        online: { badge: 'ONLINE', text: 'Takım Arkadaşı' },
        down: { badge: 'KESİK', text: 'Bağlantı Kesildi' }
    }
};

const LIMITS = {
    notifyDefault: 4500,
    notifyMin: 1200,
    notifyMax: 15000,
    bannerDefault: 3200,
    bannerMin: 1200,
    bannerMax: 8000,
    progressMin: 250,
    progressMax: 60000,
    lobbySize: 4
};

const LOCKER_CATEGORIES = [
    { key: 'all', label: STRINGS.lockerCategories.all },
    { key: 'weapon', label: STRINGS.lockerCategories.weapon },
    { key: 'ammo', label: STRINGS.lockerCategories.ammo },
    { key: 'medical', label: STRINGS.lockerCategories.medical },
    { key: 'food', label: STRINGS.lockerCategories.food },
    { key: 'utility', label: STRINGS.lockerCategories.utility },
    { key: 'misc', label: STRINGS.lockerCategories.misc }
];

const LOCKER_RULES = {
    ammo: [/(ammo|bullet|9mm|5\.56|7\.62|12g|shell|mermi)/i],
    medical: [/(med|bandage|first aid|painkiller|adrenaline|syringe|health|cream|medikal)/i],
    food: [/(water|cola|drink|food|sandwich|bread|burger|milk|juice|consume|gıda)/i],
    utility: [/(tool|lockpick|radio|phone|repair kit|repairkit|armor|z[ıi]rh|helmet|bag|utility|ekipman)/i]
};

const state = {
    currentView: 'menu',
    menuState: {},
    upgrades: [],
    recipes: [],
    craftSource: {},
    craftSearch: '',
    craftCategory: 'all',
    craftDialog: null,
    stages: [],
    selectedModeId: 'classic',
    stageModeLabel: 'Klasik Hayatta Kalma',
    players: [],
    lobbies: [],
    members: [],
    memberLeaderId: null,
    inviteLeaderId: null,
    reconnectPrompt: null,
    arcLockers: null,
    lockerCategory: 'all',
    confirmDialog: null,
    arcHud: getDefaultArcHudState(),
    arcBanner: getDefaultArcBannerState(),
    arcProgress: getDefaultArcProgressState(),
    arcBarricadePlacement: getDefaultArcBarricadeState()
};

const ui = {
    app: document.getElementById('app'),
    content: document.getElementById('content'),
    modalRoot: document.getElementById('modal-root'),
    breadcrumb: document.getElementById('breadcrumb-text'),
    screenTitle: document.getElementById('screen-title'),
    screenSubtitle: document.getElementById('screen-subtitle'),
    summaryCards: document.getElementById('summary-cards'),
    briefTitle: document.getElementById('brief-title'),
    briefText: document.getElementById('brief-text'),
    briefTag: document.getElementById('brief-tag'),
    briefBadges: document.getElementById('brief-badges'),
    briefExtraction: document.getElementById('brief-extraction'),
    briefExtractionPhase: document.getElementById('brief-extraction-phase'),
    briefExtractionObjective: document.getElementById('brief-extraction-objective'),
    briefExtractionCountdown: document.getElementById('brief-extraction-countdown'),
    briefProgressFill: document.getElementById('brief-progress-fill'),
    briefPrimaryAction: document.getElementById('brief-primary-action'),
    overlayRoot: document.getElementById('arc-overlay-root'),
    banner: document.getElementById('arc-result-banner'),
    bannerLabel: document.getElementById('arc-result-banner-label'),
    bannerTitle: document.getElementById('arc-result-banner-title'),
    progressCard: document.getElementById('arc-progress-card'),
    progressTitle: document.getElementById('arc-progress-title'),
    progressLabel: document.getElementById('arc-progress-label'),
    progressFill: document.getElementById('arc-progress-fill'),
    progressPercent: document.getElementById('arc-progress-percent'),
    progressCancel: document.getElementById('arc-progress-cancel'),
    barricadeCard: document.getElementById('arc-barricade-placement-card'),
    barricadeTitle: document.getElementById('arc-barricade-placement-title'),
    barricadeControls: document.getElementById('arc-barricade-placement-controls'),
    infoPanel: document.getElementById('arc-info-panel'),
    infoTitle: document.getElementById('arc-info-title'),
    infoSubtitle: document.getElementById('arc-info-subtitle'),
    infoLines: document.getElementById('arc-info-lines'),
    infoPrompt: document.getElementById('arc-info-prompt'),
    teamPanel: document.getElementById('arc-team-panel'),
    teamCount: document.getElementById('arc-team-count'),
    teamMembers: document.getElementById('arc-team-members'),
    notifyStack: document.getElementById('arc-notify-stack')
};

let appHideTimer = null;
let bannerTimer = null;
let progressFrame = null;
let notifyTimers = [];

const messageHandlers = {
    openMenu(data) {
        state.menuState = normalizeMenuState(data);
        state.currentView = 'menu';
        closeDialogs();
        showApp();
        renderCurrentView();
    },
    updateMenuState(data) {
        state.menuState = normalizeMenuState(data);
        if (state.currentView === 'menu') renderCurrentView();
    },
    openMarket(data) {
        state.upgrades = safeArray(data && data.upgrades);
        state.currentView = 'market';
        closeDialogs();
        showApp();
        renderCurrentView();
    },
    openCraft(data) {
        state.recipes = normalizeRecipes(data && data.recipes);
        state.craftSource = {
            sourceKey: safeString(data && data.sourceKey),
            sourceLabel: safeString(data && data.sourceLabel),
            helperText: safeString(data && data.helperText)
        };
        state.currentView = 'craft';
        state.craftDialog = null;
        showApp();
        renderCurrentView();
    },
    openStages(data) {
        state.stages = safeArray(data && data.stages);
        state.selectedModeId = safeString(data && data.modeId, 'classic');
        state.stageModeLabel = safeString(data && data.modeLabel, state.selectedModeId === 'arc_pvp' ? 'ARC Baskını' : 'Klasik Hayatta Kalma');
        state.currentView = 'stages';
        closeDialogs();
        showApp();
        renderCurrentView();
    },
    openArcLockers(data) {
        state.arcLockers = normalizeArcLockers(data);
        state.currentView = 'arcLockers';
        closeDialogs(true);
        showApp();
        renderCurrentView();
    },
    openInvite(data) {
        state.players = safeArray(data && data.players);
        state.currentView = 'invite';
        closeDialogs();
        showApp();
        renderCurrentView();
    },
    openActiveLobbies(data) {
        state.lobbies = safeArray(data && data.lobbies);
        state.currentView = 'active-lobbies';
        closeDialogs();
        showApp();
        renderCurrentView();
    },
    openMembers(data) {
        state.members = safeArray(data && data.members);
        state.memberLeaderId = data && data.leaderId != null ? Number(data.leaderId) : null;
        state.currentView = 'members';
        closeDialogs();
        showApp();
        renderCurrentView();
    },
    syncLobbyMembers(data) {
        state.members = safeArray(data && data.members);
        if (data && data.leaderId != null) state.memberLeaderId = Number(data.leaderId);
        if (state.currentView === 'members') renderCurrentView();
    },
    setArcHud(data) {
        state.arcHud = Object.assign({}, state.arcHud, data || {});
        renderOverlays();
    },
    clearArcHud() {
        clearArcHudState();
    },
    arcNotify(data) {
        pushToast(data || {});
    },
    showArcBanner(data) {
        showBanner(data || {});
    },
    clearArcBanner() {
        clearBanner();
    },
    showArcProgress(data) {
        showProgress(data || {});
    },
    hideArcProgress() {
        clearProgress();
    },
    showArcBarricadePlacement(data) {
        state.arcBarricadePlacement = {
            visible: true,
            title: safeString(data && data.title, STRINGS.barricade.title),
            controls: safeArray(data && data.controls)
        };
        renderOverlays();
    },
    hideArcBarricadePlacement() {
        state.arcBarricadePlacement = getDefaultArcBarricadeState();
        renderOverlays();
    },
    openReconnectPrompt(data) {
        state.reconnectPrompt = data || {};
        state.currentView = 'arc-reconnect';
        closeDialogs();
        showApp();
        renderCurrentView();
    },
    receiveInvite(data) {
        state.inviteLeaderId = data && data.leaderId != null ? Number(data.leaderId) : null;
        state.currentView = 'invite-received';
        closeDialogs();
        showApp();
        renderCurrentView();
    },
    closeMenu() {
        hideApp();
    }
};

window.addEventListener('message', function (event) {
    const payload = event && event.data ? event.data : {};
    const handler = messageHandlers[payload.type];
    if (!handler) {
        console.warn('[gs-survival-ui] Unknown message type:', payload.type, payload);
        return;
    }

    try {
        handler(payload.data);
    } catch (error) {
        console.warn('[gs-survival-ui] Message handler failed:', payload.type, error, payload);
    }
});

document.addEventListener('keydown', handleKeydown);
document.addEventListener('click', handleClick);
document.addEventListener('input', handleInput);
document.addEventListener('change', handleInput);
document.addEventListener('dragstart', handleDragStart);
document.addEventListener('dragover', handleDragOver);
document.addEventListener('dragleave', handleDragLeave);
document.addEventListener('drop', handleDrop);
document.addEventListener('dragend', clearDropTargets);
document.addEventListener('contextmenu', handleContextMenu);

renderCurrentView();
renderOverlays();

function getDefaultArcHudState() {
    return {
        enabled: false,
        showInfo: false,
        title: 'ARC Operasyonu',
        subtitle: 'Saha telemetrisi',
        lines: [],
        prompt: '',
        teamMembers: []
    };
}

function getDefaultArcBannerState() {
    return {
        visible: false,
        label: STRINGS.banner.label,
        title: STRINGS.banner.title,
        duration: LIMITS.bannerDefault,
        transition: false
    };
}

function getDefaultArcProgressState() {
    return {
        visible: false,
        id: 0,
        title: STRINGS.progress.title,
        label: STRINGS.progress.label,
        duration: 0,
        canCancel: true,
        startedAt: 0,
        completedNotified: false
    };
}

function getDefaultArcBarricadeState() {
    return {
        visible: false,
        title: STRINGS.barricade.title,
        controls: []
    };
}

function safeArray(value) {
    return Array.isArray(value) ? value : [];
}

function safeString(value, fallback) {
    if (value === undefined || value === null) return fallback || '';
    return String(value);
}

function safeNumber(value, fallback) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : (fallback !== undefined ? fallback : 0);
}

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function esc(value) {
    return safeString(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

function escAttr(value) {
    return esc(value).replace(/`/g, '&#096;');
}

function jsonAttr(payload) {
    return escAttr(JSON.stringify(payload || {}));
}

function formatSecondsClock(totalSeconds) {
    const seconds = Math.max(0, Math.floor(safeNumber(totalSeconds, 0)));
    const minutes = Math.floor(seconds / 60);
    return String(minutes).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
}

function formatCurrency(value) {
    return safeNumber(value, 0).toLocaleString('tr-TR');
}

function describeCount(count, singular, plural) {
    const total = Math.max(0, Math.floor(safeNumber(count, 0)));
    return total + ' ' + (total === 1 ? singular : plural);
}

function parsePayload(node) {
    if (!node) return {};
    const raw = node.getAttribute('data-ui-payload');
    if (!raw) return {};
    try {
        return JSON.parse(raw);
    } catch (error) {
        console.warn('[gs-survival-ui] Invalid element payload:', error, raw);
        return {};
    }
}

function normalizeMenuState(data) {
    const next = data || {};
    return {
        userLevel: Math.max(1, Math.floor(safeNumber(next.userLevel, 1))),
        isLeader: next.isLeader === true,
        isMember: next.isMember === true,
        hasLobby: next.hasLobby === true,
        isReady: next.isReady === true,
        playerName: safeString(next.playerName, 'Bilinmeyen Operatif'),
        currentStage: safeNumber(next.currentStage, 1),
        upgradeLabel: safeString(next.upgradeLabel, '-'),
        lobbyStatus: safeString(next.lobbyStatus, 'Tek Başına'),
        currentModeId: safeString(next.currentModeId, 'classic'),
        currentModeLabel: safeString(next.currentModeLabel, 'Klasik Hayatta Kalma'),
        arcMainStacks: safeNumber(next.arcMainStacks, 0),
        arcMainItems: safeNumber(next.arcMainItems, 0),
        arcLoadoutStacks: safeNumber(next.arcLoadoutStacks, 0),
        arcLoadoutItems: safeNumber(next.arcLoadoutItems, 0),
        arcLoadoutReady: next.arcLoadoutReady === true,
        arcLoadoutState: next.arcLoadoutState || {},
        arcSummary: next.arcSummary || {},
        arcExtraction: next.arcExtraction || {},
        allowPersonalInventory: next.allowPersonalInventory !== false,
        disconnectPolicy: safeString(next.disconnectPolicy),
        disconnectPolicyLabel: safeString(next.disconnectPolicyLabel),
        disconnectPolicyDescription: safeString(next.disconnectPolicyDescription)
    };
}

function normalizeRecipes(recipes) {
    return safeArray(recipes).map(function (recipe) {
        const next = recipe || {};
        return {
            header: safeString(next.header),
            txt: safeString(next.txt),
            item: safeString(next.item),
            amount: Math.max(1, Math.floor(safeNumber(next.amount, 1))),
            label: safeString(next.label, safeString(next.header, 'Tarif')),
            requirements: safeArray(next.requirements),
            stashId: safeString(next.stashId),
            sourceLabel: safeString(next.sourceLabel),
            category: safeString(next.category, 'misc'),
            ready: next.ready === true,
            maxCraftable: Math.max(0, Math.floor(safeNumber(next.maxCraftable, next.ready ? 1 : 0)))
        };
    });
}

function normalizeArcLockers(data) {
    const next = data || {};
    return {
        focusSide: safeString(next.focusSide, 'main') === 'loadout' ? 'loadout' : 'main',
        main: normalizeArcLockerSection(next.main || next.focused, 'main'),
        loadout: normalizeArcLockerSection(next.loadout || next.paired, 'loadout'),
        transferSupport: next.transferSupport || {},
        splitDialog: null
    };
}

function normalizeArcLockerSection(section, defaultSide) {
    const next = section || {};
    return {
        side: safeString(next.side, defaultSide),
        stashId: safeString(next.stashId),
        label: safeString(next.label, defaultSide === 'loadout' ? 'ARC Baskın Çantası' : 'ARC Kalıcı Depo'),
        title: safeString(next.title, defaultSide === 'loadout' ? 'Baskın Çantası' : 'Kalıcı Depo'),
        helperText: safeString(next.helperText),
        slots: Math.max(0, Math.floor(safeNumber(next.slots, 0))),
        items: safeArray(next.items).map(function (item) {
            const value = item || {};
            return {
                slot: Math.max(0, Math.floor(safeNumber(value.slot, 0))),
                name: safeString(value.name),
                label: safeString(value.label, safeString(value.name, 'İsimsiz Eşya')),
                count: Math.max(0, Math.floor(safeNumber(value.count, 0))),
                image: safeString(value.image),
                description: safeString(value.description),
                metadata: value.metadata || {},
                isWeapon: value.isWeapon === true,
                stackable: value.stackable !== false
            };
        })
    };
}

function showApp() {
    clearTimeout(appHideTimer);
    ui.app.classList.remove('hidden');
    requestAnimationFrame(function () {
        ui.app.classList.add('is-visible');
        ui.app.setAttribute('aria-hidden', 'false');
    });
}

function hideApp() {
    ui.app.classList.remove('is-visible');
    ui.app.setAttribute('aria-hidden', 'true');
    closeDialogs();
    clearTimeout(appHideTimer);
    appHideTimer = setTimeout(function () {
        ui.app.classList.add('hidden');
    }, 220);
}

function sendAction(action, data) {
    fetch('https://' + GetParentResourceName() + '/nuiAction', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: action, data: data || {} })
    }).catch(function (error) {
        console.warn('[gs-survival-ui] Failed to send action:', action, error);
    });
}

function closeMenu() {
    if (state.currentView === 'arc-reconnect') {
        sendAction('arcReconnectDecision', { accepted: false });
        return;
    }
    hideApp();
    sendAction('closeMenu', {});
}

function closeDialogs(keepLockerSplit) {
    state.confirmDialog = null;
    state.craftDialog = null;
    if (!keepLockerSplit && state.arcLockers) state.arcLockers.splitDialog = null;
    renderModal();
}

function renderCurrentView() {
    const renderer = viewRenderers[state.currentView] || renderMenuView;
    const view = renderer();
    ui.screenTitle.textContent = view.title || STRINGS.app.title;
    ui.screenSubtitle.textContent = view.subtitle || STRINGS.app.subtitle;
    ui.breadcrumb.textContent = view.breadcrumb || STRINGS.app.breadcrumb;
    renderSidebar(view.sidebar || buildDefaultSidebar());
    ui.content.innerHTML = view.html;
    bindImageFallbacks(ui.content);
    renderModal();
}

const viewRenderers = {
    menu: renderMenuView,
    market: renderMarketView,
    craft: renderCraftView,
    stages: renderStagesView,
    invite: renderInviteView,
    'active-lobbies': renderActiveLobbiesView,
    members: renderMembersView,
    'invite-received': renderReceiveInviteView,
    'arc-reconnect': renderReconnectView,
    'create-lobby': renderCreateLobbyView,
    arcLockers: renderArcLockersView
};

function buildDefaultSidebar() {
    return {
        cards: [
            { label: 'Karakter', value: 'Hazır', percent: 84 },
            { label: 'Takım', value: 'Solo', percent: 34 },
            { label: 'Bağlantı', value: 'Stabil', percent: 72 },
            { label: 'Hazırlık', value: 'Bekleniyor', percent: 28 }
        ],
        title: 'Operasyon Hazır',
        text: 'Takım durumunu kontrol et ve operasyona hazırlan.',
        tag: STRINGS.badge.solo,
        badges: [],
        progress: 24,
        action: 'noop',
        actionLabel: 'Bekleniyor',
        actionDisabled: true
    };
}

function renderSidebar(config) {
    const sidebar = config || buildDefaultSidebar();
    ui.summaryCards.innerHTML = safeArray(sidebar.cards).map(function (card) {
        const width = clamp(safeNumber(card.percent, 0), 0, 100);
        return '' +
            '<article class="metric-card">' +
                '<div class="metric-card__top">' +
                    '<span class="metric-card__label">' + esc(card.label || '-') + '</span>' +
                    '<span class="metric-card__value">' + esc(card.value || '-') + '</span>' +
                '</div>' +
                '<div class="ui-progress"><span class="ui-progress__fill" style="width:' + width + '%"></span></div>' +
            '</article>';
    }).join('');

    ui.briefTitle.textContent = safeString(sidebar.title, 'Operasyon Hazır');
    ui.briefText.textContent = safeString(sidebar.text, '');
    ui.briefTag.textContent = safeString(sidebar.tag, STRINGS.badge.solo);
    ui.briefBadges.innerHTML = safeArray(sidebar.badges).map(function (badge) {
        return '<span class="ui-chip">' + esc(badge && badge.label ? badge.label : badge) + '</span>';
    }).join('');
    ui.briefProgressFill.style.width = clamp(safeNumber(sidebar.progress, 0), 0, 100) + '%';

    const extraction = sidebar.extraction;
    const hasExtraction = extraction && (extraction.phase || extraction.objective || extraction.countdown);
    ui.briefExtraction.classList.toggle('hidden', !hasExtraction);
    if (hasExtraction) {
        ui.briefExtractionPhase.textContent = safeString(extraction.phase, 'Hazır');
        ui.briefExtractionObjective.textContent = safeString(extraction.objective);
        ui.briefExtractionCountdown.textContent = safeString(extraction.countdown, '00:00');
    }

    ui.briefPrimaryAction.textContent = safeString(sidebar.actionLabel, 'Bekleniyor');
    ui.briefPrimaryAction.disabled = sidebar.actionDisabled === true;
    ui.briefPrimaryAction.className = 'ui-button ui-button--primary ui-button--block';
    if (sidebar.actionVariant === 'danger') ui.briefPrimaryAction.className = 'ui-button ui-button--danger ui-button--block';
    ui.briefPrimaryAction.setAttribute('data-ui-action', safeString(sidebar.action, 'noop'));
    ui.briefPrimaryAction.setAttribute('data-ui-payload', jsonAttr(sidebar.actionPayload || {}));
}

function renderMenuView() {
    const menu = state.menuState;
    const loadoutInfo = getLoadoutInfo(menu);
    const extraction = getExtractionInfo(menu);
    const teamCards = buildMenuTeamCards(menu);

    const html = '' +
        '<div class="view-stack">' +
            renderViewHeader('Operasyon Kontrol Merkezi', 'Menü, lobi, market, stage ve ARC hazırlık akışları yeni component diliyle yeniden düzenlendi.') +
            '<div class="view-grid">' +
                '<section class="panel-section span-7">' +
                    '<div class="panel-section__header">' +
                        '<div><p class="ui-overline">Hazırlık</p><h3 class="ui-card__title">Operasyon Akışları</h3><p class="ui-card__text">Hayatta kalma ve ARC akışlarını aynı merkezden yönet.</p></div>' +
                    '</div>' +
                    '<div class="card-grid">' +
                        renderActionCard('Klasik Operasyon', 'Stage seç, takımını hazırla ve dalga modunu başlat.', [
                            'Seviye ' + menu.userLevel,
                            menu.currentModeLabel
                        ], button('Stage Seç', 'open-stages', { modeId: 'classic' }, 'primary')) +
                        renderActionCard('Market', 'Saha güçlendirmelerini kredi ile satın al.', [
                            menu.upgradeLabel || '-',
                            'Hazırlık'
                        ], button('Marketi Aç', 'open-market', {}, 'ghost')) +
                        renderActionCard('Atölye', 'Topladığın malzemelerle ekipman üret.', [
                            state.craftSource.sourceLabel || 'Standart Atölye',
                            'Üretim'
                        ], button('Atölyeyi Aç', 'open-craft', {}, 'ghost')) +
                    '</div>' +
                '</section>' +
                '<section class="panel-section span-5">' +
                    '<div class="panel-section__header">' +
                        '<div><p class="ui-overline">Özet</p><h3 class="ui-card__title">Operatör Durumu</h3><p class="ui-card__text">Lobi, seviye ve tahliye bilgisinin kısa özeti.</p></div>' +
                    '</div>' +
                    '<div class="status-grid">' +
                        renderStat('Operatör', menu.playerName, clamp(36 + menu.playerName.length * 4, 20, 100)) +
                        renderStat('Lobi', menu.lobbyStatus, menu.hasLobby ? 84 : 32) +
                        renderStat('ARC Çanta', loadoutInfo.badge, loadoutInfo.percent) +
                        renderStat('Tahliye', extraction.phase || 'Pasif', extraction.percent) +
                    '</div>' +
                '</section>' +
                '<section class="panel-section span-12">' +
                    '<div class="panel-section__header">' +
                        '<div><p class="ui-overline">ARC</p><h3 class="ui-card__title">Baskın Hazırlığı</h3><p class="ui-card__text">Loadout, depo ve craft akışlarını kayıpsız sözleşmeyle yönet.</p></div>' +
                    '</div>' +
                    '<div class="card-grid">' +
                        renderActionCard('ARC Baskını', 'Takımın ve loadout çantan hazırsa baskını başlat.', [
                            loadoutInfo.badge,
                            menu.allowPersonalInventory ? 'TAB Açık' : 'TAB Kapalı'
                        ], button('ARC Baskınını Başlat', 'start-arc', {}, 'primary')) +
                        renderActionCard('Baskın Çantası', 'Girişte üstüne verilecek ekipmanı yönet.', [
                            'Stack: ' + menu.arcLoadoutStacks,
                            'Eşya: ' + menu.arcLoadoutItems
                        ], button('Çantayı Aç', 'open-loadout-stash', {}, 'ghost')) +
                        renderActionCard('ARC Atölyesi', 'Kalıcı depodaki malzemeleri baskın ekipmanına dönüştür.', [
                            'Stack: ' + menu.arcMainStacks,
                            'Eşya: ' + menu.arcMainItems
                        ], button('ARC Craft Aç', 'open-arc-craft', { source: 'arc_main' }, 'ghost')) +
                        renderActionCard('Kalıcı Depo', 'Kalıcı loot akışını ve baskın hazırlığını düzenle.', [
                            'Main Depo',
                            'Sabit'
                        ], button('Depoyu Aç', 'open-main-stash', {}, 'ghost')) +
                    '</div>' +
                '</section>' +
                '<section class="panel-section span-12">' +
                    '<div class="panel-section__header">' +
                        '<div><p class="ui-overline">Takım</p><h3 class="ui-card__title">Lobi Yönetimi</h3><p class="ui-card__text">Kur, davet et, listele, ayrıl veya dağıt.</p></div>' +
                    '</div>' +
                    '<div class="card-grid">' + teamCards + '</div>' +
                '</section>' +
            '</div>' +
        '</div>';

    return {
        title: 'Ana Menü',
        subtitle: 'Tüm hazırlık akışları tutarlı kart hiyerarşisiyle yenilendi.',
        breadcrumb: STRINGS.app.breadcrumb,
        sidebar: {
            cards: [
                { label: 'Seviye', value: 'Lv.' + menu.userLevel, percent: clamp(28 + menu.userLevel * 6, 18, 100) },
                { label: 'Takım', value: menu.hasLobby ? 'Bağlı' : 'Solo', percent: menu.hasLobby ? 84 : 30 },
                { label: 'ARC', value: loadoutInfo.shortLabel, percent: loadoutInfo.percent },
                { label: 'Tahliye', value: extraction.phase || 'Pasif', percent: extraction.percent }
            ],
            title: menu.currentModeId === 'arc_pvp' ? 'ARC Baskın Hazırlığı' : 'Operasyon Hazır',
            text: menu.currentModeId === 'arc_pvp'
                ? menu.currentModeLabel + ' seçili. ' + loadoutInfo.detail
                : menu.currentModeLabel + ' seçili. Takımını düzenle ve operasyona hazırlan.',
            tag: menu.isLeader ? STRINGS.badge.leader : (menu.isMember ? STRINGS.badge.team : STRINGS.badge.solo),
            badges: [
                { label: menu.lobbyStatus },
                { label: loadoutInfo.badge },
                { label: menu.disconnectPolicyLabel || 'Bağlantı Politikası' }
            ],
            progress: menu.hasLobby ? 70 : 42,
            action: menu.isMember ? 'toggle-ready' : 'noop',
            actionLabel: menu.isMember ? (menu.isReady ? 'Hazır Değil Yap' : 'Hazır Ol') : (menu.isLeader ? 'Lider Kontrolü' : 'Solo Mod'),
            actionDisabled: !menu.isMember,
            extraction: extraction.phase ? extraction : null
        },
        html: html
    };
}

function renderMarketView() {
    const cards = state.upgrades.length ? state.upgrades.map(function (upgrade, index) {
        const value = clamp(44 + index * 11, 18, 96);
        return '' +
            '<article class="item-card">' +
                '<div class="item-card__header">' +
                    '<div><p class="ui-overline">Market</p><h3 class="item-card__title">' + esc(upgrade.label || 'Yükseltme') + '</h3></div>' +
                    '<span class="ui-badge ui-badge--primary">$' + esc(formatCurrency(upgrade.price)) + '</span>' +
                '</div>' +
                '<p class="ui-card__text">Satın alındığında takımına doğrudan saha avantajı sağlar.</p>' +
                renderMeter(value) +
                '<div class="card-list__chips">' +
                    '<span class="ui-chip">Tür: ' + esc(upgrade.type || '-') + '</span>' +
                    '<span class="ui-chip">Değer: ' + esc(upgrade.value || '-') + '</span>' +
                '</div>' +
                '<div class="card-list__actions">' + button('Satın Al', 'buy-upgrade', { index: index }, 'primary') + '</div>' +
            '</article>';
    }).join('') : renderEmptyState('🛒', STRINGS.empty.market);

    return {
        title: 'Market',
        subtitle: 'Fiyat ve satın alma onay akışı modern kart görünümüyle yenilendi.',
        breadcrumb: 'Operasyon Menüsü / Market',
        sidebar: buildStandardSidebar('Saha Marketi', 'Güçlendirmeleri satın al ve bir sonraki çatışma için avantaj kazan.', 'PAZAR', 68, [
            { label: 'Ürün', value: describeCount(state.upgrades.length, 'ürün', 'ürün'), percent: clamp(state.upgrades.length * 16, 18, 100) },
            { label: 'Takım', value: state.menuState.lobbyStatus || 'Solo', percent: state.menuState.hasLobby ? 78 : 32 },
            { label: 'Hazırlık', value: 'Aktif', percent: 84 },
            { label: 'Mod', value: state.menuState.currentModeLabel || '-', percent: 72 }
        ]),
        html: '<div class="view-stack">' +
            renderViewHeader('Saha Marketi', 'Kartlar üzerinden fiyat, etki ve satın alma adımlarını takip et.', button('Ana Menüye Dön', 'go-back', {}, 'ghost')) +
            '<div class="card-grid">' + cards + '</div>' +
        '</div>'
    };
}

function renderCraftView() {
    const filtered = getFilteredRecipes();
    const sourceLabel = state.craftSource.sourceLabel || 'Atölye';
    const sourceKey = state.craftSource.sourceKey || '';
    const isArcCraft = sourceKey.indexOf('arc_') === 0;
    const cards = filtered.length ? filtered.map(function (recipe) {
        const index = state.recipes.indexOf(recipe);
        const maxCraftable = Math.max(0, safeNumber(recipe.maxCraftable, recipe.ready ? 1 : 0));
        const ready = recipe.ready === true || maxCraftable > 0;
        return '' +
            '<article class="item-card">' +
                '<div class="item-card__header">' +
                    '<div><p class="ui-overline">' + esc(getCraftCategoryLabel(recipe.category)) + '</p><h3 class="item-card__title">' + esc(recipe.label || recipe.header || 'Tarif') + '</h3></div>' +
                    '<span class="ui-badge ' + (ready ? 'ui-badge--success' : 'ui-badge--warning') + '">' + esc(ready ? 'Hazır' : 'Eksik') + '</span>' +
                '</div>' +
                '<p class="ui-card__text">' + esc(recipe.txt || 'Saha kullanımı için hazırlanabilen ekipman paketi.') + '</p>' +
                '<div class="card-list__chips">' +
                    '<span class="ui-chip">Çıktı: x' + esc(recipe.amount) + '</span>' +
                    '<span class="ui-chip">Maks: x' + esc(maxCraftable) + '</span>' +
                    '<span class="ui-chip">' + esc(isArcCraft ? 'Kaynak: Depo' : 'Kaynak: Envanter') + '</span>' +
                '</div>' +
                '<div class="item-card__requirements">' + renderRequirements(recipe.requirements, isArcCraft) + '</div>' +
                '<div class="card-list__actions">' + button(ready ? 'Üret' : 'Yetersiz', 'craft-open', { index: index }, ready ? 'primary' : 'ghost', !ready) + '</div>' +
            '</article>';
    }).join('') : renderEmptyState('🧰', STRINGS.empty.craft);

    return {
        title: 'Atölye',
        subtitle: 'Kategori, arama ve adet seçimi akışı sadeleştirildi.',
        breadcrumb: 'Operasyon Menüsü / Atölye',
        sidebar: buildStandardSidebar(sourceLabel, state.craftSource.helperText || 'Malzemelerini kullanarak ekipman üret.', isArcCraft ? 'ARC' : 'CRAFT', isArcCraft ? 74 : 60, [
            { label: 'Tarif', value: describeCount(state.recipes.length, 'tarif', 'tarif'), percent: clamp(state.recipes.length * 8, 20, 100) },
            { label: 'Hazır', value: describeCount(countReadyRecipes(), 'tarif', 'tarif'), percent: clamp(countReadyRecipes() * 12, 18, 100) },
            { label: 'Filtre', value: getCraftCategoryLabel(state.craftCategory), percent: 64 },
            { label: 'Arama', value: state.craftSearch ? 'Aktif' : 'Kapalı', percent: state.craftSearch ? 86 : 22 }
        ]),
        html: '<div class="view-stack">' +
            renderViewHeader(sourceLabel, 'Arama, kategori ve gereksinim görünümü tek akışta toplandı.', button('Ana Menüye Dön', 'go-back', {}, 'ghost')) +
            '<section class="panel-section">' +
                '<div class="toolbar">' +
                    '<div class="toolbar__left"><input class="ui-input" type="text" value="' + escAttr(state.craftSearch) + '" placeholder="Tarif ara..." data-craft-search="1"></div>' +
                    '<div class="toolbar__right toolbar__chips">' + renderCraftFilterChips() + '</div>' +
                '</div>' +
            '</section>' +
            '<div class="card-grid">' + cards + '</div>' +
        '</div>'
    };
}

function renderStagesView() {
    const isArc = state.selectedModeId === 'arc_pvp';
    const cards = state.stages.length ? state.stages.map(function (stage, index) {
        return renderStageCard(stage, index, isArc);
    }).join('') : renderEmptyState('📍', STRINGS.empty.stages);

    return {
        title: isArc ? 'ARC Baskını' : 'Stage Seçimi',
        subtitle: 'Zorluk ve kilit bilgisi daha net kartlarda gösterilir.',
        breadcrumb: isArc ? 'ARC Menüsü / Baskın Başlat' : 'Operasyon Menüsü / Stage Seçimi',
        sidebar: buildStandardSidebar(state.stageModeLabel, isArc ? 'ARC baskını sabit ayarlarla başlar.' : 'Takımına uygun stage seç ve operasyona başla.', isArc ? 'ARC' : 'STAGE', 82, [
            { label: 'Stage', value: describeCount(state.stages.length, 'seçenek', 'seçenek'), percent: clamp(state.stages.length * 18, 20, 100) },
            { label: 'Seviye', value: 'Lv.' + safeNumber(state.menuState.userLevel, 1), percent: clamp(28 + safeNumber(state.menuState.userLevel, 1) * 6, 18, 100) },
            { label: 'Takım', value: state.menuState.lobbyStatus || 'Solo', percent: state.menuState.hasLobby ? 76 : 30 },
            { label: 'Mod', value: state.stageModeLabel, percent: isArc ? 100 : 74 }
        ]),
        html: '<div class="view-stack">' +
            renderViewHeader(state.stageModeLabel, 'Kartlar önerilen seviye, risk ve başlatma aksiyonunu ayrıştırır.', button('Ana Menüye Dön', 'go-back', {}, 'ghost')) +
            '<div class="stage-grid">' + cards + '</div>' +
        '</div>'
    };
}

function renderInviteView() {
    const cards = state.players.length ? state.players.map(function (player, index) {
        return '' +
            '<article class="member-card">' +
                '<div class="member-card__header">' +
                    '<div><p class="ui-overline">Yakındaki Oyuncu</p><h3 class="member-card__title">' + esc(player.name || 'Bilinmeyen Oyuncu') + '</h3></div>' +
                    '<span class="ui-badge ui-badge--muted">ID ' + esc(player.id || '-') + '</span>' +
                '</div>' +
                '<p class="ui-card__text">Yakındaysa daveti kabul ettiğinde doğrudan takımına katılabilir.</p>' +
                '<div class="card-list__actions">' + button('Davet Gönder', 'invite-player', { index: index }, 'primary') + '</div>' +
            '</article>';
    }).join('') : renderEmptyState('🤝', STRINGS.empty.invite);

    return {
        title: 'Davet',
        subtitle: 'Yakındaki oyuncular sade liste kartlarıyla yenilendi.',
        breadcrumb: 'Operasyon Menüsü / Davet',
        sidebar: buildStandardSidebar('Yakındaki Oyuncular', 'Yakındaki oyuncuları seçerek takım daveti gönder.', 'DAVET', 62, [
            { label: 'Oyuncu', value: describeCount(state.players.length, 'kişi', 'kişi'), percent: clamp(state.players.length * 18, 20, 100) },
            { label: 'Lider', value: state.menuState.isLeader ? 'Evet' : 'Hayır', percent: state.menuState.isLeader ? 100 : 20 },
            { label: 'Lobi', value: state.menuState.lobbyStatus || 'Solo', percent: state.menuState.hasLobby ? 80 : 24 },
            { label: 'Tarama', value: 'Canlı', percent: 88 }
        ]),
        html: '<div class="view-stack">' +
            renderViewHeader('Yakındaki Oyuncular', 'Takım daveti gönderebileceğin oyuncular burada listelenir.', button('Ana Menüye Dön', 'go-back', {}, 'ghost')) +
            '<div class="card-grid">' + cards + '</div>' +
        '</div>'
    };
}

function renderActiveLobbiesView() {
    const cards = state.lobbies.length ? state.lobbies.map(function (lobby, index) {
        const maxPlayers = Math.max(1, safeNumber(lobby.maxPlayers, LIMITS.lobbySize));
        const fill = clamp((safeNumber(lobby.playerCount, 1) / maxPlayers) * 100, 0, 100);
        return '' +
            '<article class="lobby-card">' +
                '<div class="lobby-card__header">' +
                    '<div><p class="ui-overline">Aktif Lobi</p><h3 class="lobby-card__title">' + esc(lobby.leaderName || 'Bilinmeyen Lider') + '</h3></div>' +
                    '<span class="ui-badge ' + getLobbyBadgeClass(lobby) + '">' + esc(getLobbyBadgeText(lobby)) + '</span>' +
                '</div>' +
                '<p class="ui-card__text">Lider ID: ' + esc(lobby.leaderId || '-') + ' · Hazır oyuncu: ' + esc(lobby.readyCount || 0) + '</p>' +
                '<div class="ui-progress"><span class="ui-progress__fill" style="width:' + fill + '%"></span></div>' +
                '<div class="lobby-card__meta">' +
                    renderMetaRow('Görünürlük', lobby.isPublic ? 'Herkese Açık' : 'Özel') +
                    renderMetaRow('Oyuncu', safeNumber(lobby.playerCount, 1) + '/' + maxPlayers) +
                    renderMetaRow('Üye', safeNumber(lobby.memberCount, 0)) +
                    renderMetaRow('Hazır', safeNumber(lobby.readyCount, 0)) +
                '</div>' +
                '<div class="card-list__actions">' +
                    (lobby.canJoin ? button('Lobiye Katıl', 'join-lobby-open', { index: index }, 'primary') : button('Katılım Kapalı', 'noop', {}, 'ghost', true)) +
                '</div>' +
            '</article>';
    }).join('') : renderEmptyState('🏠', STRINGS.empty.lobbies);

    return {
        title: 'Aktif Lobiler',
        subtitle: 'Public lobi görünürlüğü ve katılım durumu netleştirildi.',
        breadcrumb: 'Operasyon Menüsü / Aktif Lobiler',
        sidebar: buildStandardSidebar('Açık Lobi İzleme', 'Sunucudaki aktif lobileri, liderlerini ve doluluk durumlarını takip et.', 'LOBİLER', 70, [
            { label: 'Lobi', value: describeCount(state.lobbies.length, 'lobi', 'lobi'), percent: clamp(state.lobbies.length * 18, 20, 100) },
            { label: 'Takım', value: state.menuState.lobbyStatus || 'Solo', percent: state.menuState.hasLobby ? 78 : 30 },
            { label: 'Yakınlık', value: 'Kontrol', percent: 84 },
            { label: 'Hazır', value: 'Canlı', percent: 82 }
        ]),
        html: '<div class="view-stack">' +
            renderViewHeader('Aktif Lobiler', 'Katılabilir, bağlı ve kendi lobi durumları görsel olarak ayrılır.', button('Ana Menüye Dön', 'go-back', {}, 'ghost')) +
            '<div class="card-grid">' + cards + '</div>' +
        '</div>'
    };
}

function renderMembersView() {
    const cards = state.members.length ? state.members.map(function (member) {
        const isLeader = Number(member.id) === Number(state.memberLeaderId) || member.isLeader === true;
        const statusText = isLeader ? 'Lider' : (member.isReady ? 'Hazır' : 'Bekleniyor');
        const statusClass = isLeader ? 'is-leader' : (member.isReady ? 'is-ready' : 'is-waiting');
        return '' +
            '<article class="member-card">' +
                '<div class="member-card__header">' +
                    '<div><p class="ui-overline">Takım Üyesi</p><h3 class="member-card__title">' + esc(member.name || 'Bilinmeyen Operatör') + '</h3></div>' +
                    '<span class="ui-badge ' + (isLeader ? 'ui-badge--primary' : (member.isReady ? 'ui-badge--success' : 'ui-badge--warning')) + '">' + esc(statusText) + '</span>' +
                '</div>' +
                '<div class="member-card__meta">' +
                    renderMetaRow('ID', member.id || '-') +
                    renderMetaRow('Rol', isLeader ? 'Lider' : 'Üye') +
                    renderMetaRow('Durum', '<span class="member-card__status ' + statusClass + '">' + esc(statusText) + '</span>', true) +
                '</div>' +
            '</article>';
    }).join('') : renderEmptyState('👥', STRINGS.empty.members);

    return {
        title: 'Takım',
        subtitle: 'Lider ve hazır bilgisi daha net kartlarla gösteriliyor.',
        breadcrumb: 'Operasyon Menüsü / Takım',
        sidebar: buildStandardSidebar('Takım Durumu', 'Takımdaki oyuncuları ve lider bilgisini buradan kontrol et.', 'TAKIM', 74, [
            { label: 'Oyuncu', value: describeCount(state.members.length, 'kişi', 'kişi'), percent: clamp(state.members.length * 20, 18, 100) },
            { label: 'Hazır', value: describeCount(countReadyMembers(), 'kişi', 'kişi'), percent: clamp(countReadyMembers() * 18, 18, 100) },
            { label: 'Lider', value: state.memberLeaderId || '-', percent: 92 },
            { label: 'Lobi', value: state.menuState.lobbyStatus || 'Solo', percent: state.menuState.hasLobby ? 82 : 30 }
        ]),
        html: '<div class="view-stack">' +
            renderViewHeader('Takım Oyuncuları', 'Takım üyeleri hazır durumlarıyla birlikte listelenir.', button('Ana Menüye Dön', 'go-back', {}, 'ghost')) +
            '<div class="card-grid">' + cards + '</div>' +
        '</div>'
    };
}

function renderReceiveInviteView() {
    return {
        title: 'Gelen Davet',
        subtitle: 'Kabul / red akışı standart modal diliyle yeniden tasarlandı.',
        breadcrumb: 'Operasyon Menüsü / Gelen Davet',
        sidebar: buildStandardSidebar('Takım Daveti Alındı', 'Başka bir lider seni takımına çağırıyor. Daveti kabul edebilir veya reddedebilirsin.', 'UYARI', 88, [
            { label: 'Lider ID', value: state.inviteLeaderId || '-', percent: 82 },
            { label: 'Karar', value: 'Bekleniyor', percent: 50 },
            { label: 'Lobi', value: state.menuState.lobbyStatus || 'Solo', percent: 36 },
            { label: 'Durum', value: 'Canlı Davet', percent: 96 }
        ]),
        html: '<div class="view-stack">' +
            renderViewHeader('Takım Daveti', 'Davet geldiğinde ekrandan doğrudan karar verebilirsin.') +
            '<article class="modal">' +
                '<div class="modal__header">' +
                    '<div><p class="ui-overline">Davet</p><h3 class="modal__title">Takıma Katılmak İstiyor musun?</h3></div>' +
                    '<span class="ui-badge ui-badge--primary">ID ' + esc(state.inviteLeaderId || '-') + '</span>' +
                '</div>' +
                '<div class="modal__content"><p class="modal__text">Bir takım lideri seni ekibine çağırıyor. Kabul ettiğinde o lobiye katılırsın.</p></div>' +
                '<div class="modal__actions">' +
                    button('Daveti Kabul Et', 'accept-invite', {}, 'primary') +
                    button('Daveti Reddet', 'deny-invite', {}, 'danger') +
                '</div>' +
            '</article>' +
        '</div>'
    };
}

function renderReconnectView() {
    const prompt = state.reconnectPrompt || {};
    const extraction = prompt.extraction || {};
    return {
        title: 'Geri Katılım',
        subtitle: 'ARC reconnect kararı daha okunabilir kartlarla sunulur.',
        breadcrumb: 'ARC Bağlantı / Geri Katılım',
        sidebar: buildStandardSidebar('ARC Geri Katılım Onayı', 'Bağlantın koptu. Uygunsa aynı baskına geri dönebilirsin.', 'UYARI', 90, [
            { label: 'Mod', value: safeString(prompt.modeId, 'ARC'), percent: 92 },
            { label: 'Tahliye', value: safeString(extraction.phaseLabel, 'Bilinmiyor'), percent: extraction.phaseLabel ? 76 : 24 },
            { label: 'Karar', value: 'Bekleniyor', percent: 50 },
            { label: 'Politika', value: safeString(prompt.disconnectPolicyLabel, 'Varsayılan'), percent: 80 }
        ]),
        html: '<div class="view-stack">' +
            renderViewHeader('Baskına Geri Katıl', 'Uygunsa aynı ARC baskınına kaldığın yerden dönersin.') +
            '<article class="modal">' +
                '<div class="modal__header">' +
                    '<div><p class="ui-overline">Reconnect</p><h3 class="modal__title">' + esc(prompt.title || 'Oyuna geri katılmak ister misin?') + '</h3></div>' +
                    '<span class="ui-badge ui-badge--warning">Karar Gerekli</span>' +
                '</div>' +
                '<div class="modal__content">' +
                    '<p class="modal__text">' + esc(prompt.message || 'Bağlantın koptu. Aynı baskına geri katılmak ister misin?') + '</p>' +
                    (extraction.phaseLabel ? '<div class="dialog-stats"><div class="dialog-stats__item"><span class="status-grid__label">Son Tahliye Fazı</span><strong class="status-grid__value">' + esc(extraction.phaseLabel) + '</strong></div></div>' : '') +
                '</div>' +
                '<div class="modal__actions">' +
                    button('Evet, Katıl', 'reconnect-decision', { accepted: true }, 'primary') +
                    button('Hayır, Güvenli Dön', 'reconnect-decision', { accepted: false }, 'danger') +
                '</div>' +
            '</article>' +
        '</div>'
    };
}

function renderCreateLobbyView() {
    return {
        title: 'Lobi Kur',
        subtitle: 'Public / private seçimi sade kartlarla yenilendi.',
        breadcrumb: 'Operasyon Menüsü / Lobi Kur',
        sidebar: buildStandardSidebar('Lobi Görünürlüğü', 'Lobi türünü seç. Kurulum tamamlandığında ana ekrana dönersin.', 'TAKIM', 58, [
            { label: 'Oyuncu Sınırı', value: LIMITS.lobbySize + ' kişi', percent: 100 },
            { label: 'Kurulum', value: '1 adım', percent: 78 },
            { label: 'Davetiye', value: 'Hazır', percent: 88 },
            { label: 'Akış', value: 'Hızlı', percent: 84 }
        ]),
        html: '<div class="view-stack">' +
            renderViewHeader('Lobi Görünürlüğünü Seç', 'Herkese açık lobi listede görünür; özel lobi yalnızca davet kabul eden oyuncular içindir.', button('Ana Menüye Dön', 'go-back', {}, 'ghost')) +
            '<div class="card-grid">' +
                renderActionCard('Herkese Açık Lobi', 'Aktif lobi listesinde görünür ve boş slot varsa doğrudan katılım alabilir.', [
                    'Liste Üzerinden Katılım',
                    'Hızlı Dolum'
                ], button('Public Lobi Kur', 'create-lobby', { isPublic: true }, 'primary')) +
                renderActionCard('Özel Lobi', 'Yalnızca senin gönderdiğin daveti kabul eden oyuncular katılır.', [
                    'Davet Tabanlı',
                    'Kapalı Ekip'
                ], button('Private Lobi Kur', 'create-lobby', { isPublic: false }, 'ghost')) +
            '</div>' +
        '</div>'
    };
}

function renderArcLockersView() {
    const lockers = state.arcLockers || normalizeArcLockers({});
    const focusSide = lockers.focusSide === 'loadout' ? 'loadout' : 'main';
    const otherSide = focusSide === 'loadout' ? 'main' : 'loadout';

    return {
        title: 'ARC Depo Yönetimi',
        subtitle: 'Kalıcı depo ve baskın çantası aynı component sistemiyle yenilendi.',
        breadcrumb: 'Operasyon Menüsü / ARC Depo Yönetimi',
        sidebar: buildStandardSidebar(focusSide === 'loadout' ? lockers.loadout.label : lockers.main.label, lockers.transferSupport.helperText || 'Taşıma, stackleme ve split akışı korunur.', focusSide === 'loadout' ? 'LOADOUT' : 'STASH', 82, [
            { label: 'Odak', value: focusSide === 'loadout' ? 'Baskın Çantası' : 'Kalıcı Depo', percent: 100 },
            { label: 'Main', value: describeCount(lockers.main.items.length, 'slot', 'slot'), percent: getLockerUsage(lockers.main) },
            { label: 'Loadout', value: describeCount(lockers.loadout.items.length, 'slot', 'slot'), percent: getLockerUsage(lockers.loadout) },
            { label: 'Filtre', value: getLockerCategoryLabel(state.lockerCategory), percent: 66 }
        ]),
        html: '<div class="view-stack">' +
            renderViewHeader('ARC Depo Yönetimi', 'Drag & drop, yığın ayırma ve odak değişimi mevcut callback sözleşmesini korur.', button('Ana Menüye Dön', 'go-back', {}, 'ghost')) +
            '<section class="locker-toolbar">' +
                '<div><p class="ui-overline">Odak</p><h3 class="ui-card__title">' + esc(focusSide === 'loadout' ? lockers.loadout.label : lockers.main.label) + '</h3><p class="ui-card__text">' + esc(lockers.transferSupport.helperText || 'Sol tık taşıma, sağ tık split ve sürükle-bırak desteklenir.') + '</p></div>' +
                '<div class="locker-actions">' +
                    button('Yenile', 'refresh-lockers', { focusSide: focusSide }, 'ghost') +
                    button(otherSide === 'loadout' ? 'Baskın Çantasına Geç' : 'Kalıcı Depoya Geç', 'swap-locker-focus', { focusSide: otherSide }, 'ghost') +
                '</div>' +
            '</section>' +
            '<div class="locker-filters">' + renderLockerFilterChips() + '</div>' +
            '<div class="locker-grid">' +
                renderLockerPanel(lockers.main, focusSide) +
                renderLockerPanel(lockers.loadout, focusSide) +
            '</div>' +
        '</div>'
    };
}

function buildStandardSidebar(title, text, tag, progress, cards) {
    return {
        cards: cards,
        title: title,
        text: text,
        tag: tag,
        badges: [],
        progress: progress,
        action: 'noop',
        actionLabel: 'Bilgi',
        actionDisabled: true
    };
}

function renderViewHeader(title, text, actionHtml) {
    return '' +
        '<section class="view-header">' +
            '<div><p class="ui-overline">Ekran</p><h2 class="view-header__title">' + esc(title) + '</h2><p class="view-header__text">' + esc(text) + '</p></div>' +
            (actionHtml ? '<div class="panel-section__actions">' + actionHtml + '</div>' : '') +
        '</section>';
}

function renderActionCard(title, text, badges, actionHtml) {
    return '' +
        '<article class="card-list">' +
            '<div class="card-list__header"><div><p class="ui-overline">Aksiyon</p><h3 class="card-list__title">' + esc(title) + '</h3></div></div>' +
            '<p class="card-list__description">' + esc(text) + '</p>' +
            '<div class="card-list__chips">' + safeArray(badges).map(function (badge) {
                return '<span class="ui-chip">' + esc(badge) + '</span>';
            }).join('') + '</div>' +
            '<div class="card-list__actions">' + actionHtml + '</div>' +
        '</article>';
}

function renderStat(label, value, percent) {
    return '' +
        '<div class="status-grid__item">' +
            '<span class="status-grid__label">' + esc(label) + '</span>' +
            '<strong class="status-grid__value">' + esc(value) + '</strong>' +
            renderMeter(percent) +
        '</div>';
}

function renderMeter(percent) {
    return '<div class="ui-progress"><span class="ui-progress__fill" style="width:' + clamp(safeNumber(percent, 0), 0, 100) + '%"></span></div>';
}

function renderMetaRow(label, value, raw) {
    return '' +
        '<div class="meta-list__item">' +
            '<span class="list-meta__label">' + esc(label) + '</span>' +
            '<strong class="list-meta__value">' + (raw ? value : esc(value)) + '</strong>' +
        '</div>';
}

function renderEmptyState(icon, text) {
    return '' +
        '<div class="empty-state">' +
            '<div class="empty-state__icon">' + esc(icon) + '</div>' +
            '<div class="empty-state__text">' + esc(text) + '</div>' +
        '</div>';
}

function button(label, action, payload, variant, disabled) {
    let className = 'ui-button';
    if (variant === 'primary') className += ' ui-button--primary';
    else if (variant === 'danger') className += ' ui-button--danger';
    else className += ' ui-button--ghost';

    return '<button class="' + className + '" type="button" data-ui-action="' + escAttr(action) + '" data-ui-payload="' + jsonAttr(payload) + '"' + (disabled ? ' disabled' : '') + '>' + esc(label) + '</button>';
}

function getLoadoutInfo(menu) {
    const loadoutState = menu.arcLoadoutState || {};
    if (loadoutState.isReady) {
        return {
            badge: 'Çanta Hazır',
            shortLabel: 'Hazır',
            detail: 'Hazırladığın ekipman baskın girişinde üstüne verilecek.',
            percent: 94
        };
    }
    if (loadoutState.usesFallback) {
        return {
            badge: 'Yedek Paket',
            shortLabel: 'Yedek',
            detail: 'Çanta boşsa varsayılan başlangıç paketi kullanılacak.',
            percent: 58
        };
    }
    return {
        badge: 'Eksik Hazırlık',
        shortLabel: 'Eksik',
        detail: 'Baskın öncesi çantanı kontrol et.',
        percent: 34
    };
}

function getExtractionInfo(menu) {
    const extraction = menu.arcExtraction || (menu.arcSummary && menu.arcSummary.extraction) || {};
    const countdown = safeNumber(extraction.countdown, 0) > 0
        ? formatSecondsClock(extraction.countdown)
        : (safeNumber(extraction.availableIn, 0) > 0 ? formatSecondsClock(extraction.availableIn) : 'READY');
    return {
        phase: extraction.enabled === true ? safeString(extraction.phaseLabel, 'Tahliye Hazır') : '',
        objective: extraction.enabled === true ? safeString(extraction.objective, '') : '',
        countdown: extraction.enabled === true ? countdown : '',
        percent: extraction.enabled === true ? 82 : 18
    };
}

function buildMenuTeamCards(menu) {
    const cards = [
        renderActionCard('Takım Oyuncuları', 'Takımdaki oyuncuları, lideri ve hazır durumunu görüntüle.', [
            menu.hasLobby ? 'Lobi Aktif' : 'Lobi Yok',
            'Telemetri'
        ], button('Takımı Gör', 'open-members', {}, 'ghost', !menu.hasLobby)),
        renderActionCard('Aktif Lobiler', 'Sunucuda açık olan lobileri ve doluluklarını listele.', [
            'Sunucu Tarama',
            'Public / Private'
        ], button('Lobileri Listele', 'open-active-lobbies', {}, 'ghost'))
    ];

    if (menu.isLeader) {
        cards.push(
            renderActionCard('Oyuncu Davet Et', 'Yakındaki oyunculara takım daveti gönder.', [
                'Lider Yetkisi',
                'Yakın Oyuncular'
            ], button('Davet Listesini Aç', 'open-invite', {}, 'primary')),
            renderActionCard('Lobiyi Dağıt', 'Mevcut lobiyi tamamen kapat.', [
                'Riskli Aksiyon',
                'Onay Gerektirir'
            ], button('Lobiyi Dağıt', 'request-disband', {}, 'danger'))
        );
    } else if (menu.isMember) {
        cards.push(
            renderActionCard('Lobiden Ayrıl', 'Mevcut lobiden ayrılıp solo moda dön.', [
                'Üye Aksiyonu',
                'Onay Gerektirir'
            ], button('Lobiden Ayrıl', 'request-leave', {}, 'danger'))
        );
    } else {
        cards.push(
            renderActionCard('Yeni Lobi Kur', 'Public veya private yeni lobi oluştur.', [
                'En Fazla ' + LIMITS.lobbySize + ' Oyuncu',
                'Kurulum'
            ], button('Lobi Kur', 'show-create-lobby', {}, 'primary'))
        );
    }

    return cards.join('');
}

function countReadyRecipes() {
    return state.recipes.filter(function (recipe) {
        return recipe.ready === true || safeNumber(recipe.maxCraftable, 0) > 0;
    }).length;
}

function countReadyMembers() {
    return state.members.filter(function (member) {
        return member.isReady === true;
    }).length;
}

function getCraftCategoryLabel(key) {
    return STRINGS.craftCategories[key] || STRINGS.craftCategories.misc;
}

function renderCraftFilterChips() {
    const categories = { all: true };
    state.recipes.forEach(function (recipe) {
        categories[safeString(recipe.category, 'misc')] = true;
    });

    return Object.keys(categories).map(function (key) {
        return '<button class="ui-chip' + (state.craftCategory === key ? ' is-active' : '') + '" type="button" data-ui-action="craft-category" data-ui-payload="' + jsonAttr({ category: key }) + '">' + esc(getCraftCategoryLabel(key)) + '</button>';
    }).join('');
}

function getFilteredRecipes() {
    const search = safeString(state.craftSearch).trim().toLowerCase();
    return state.recipes.filter(function (recipe) {
        const category = safeString(recipe.category, 'misc');
        const text = [recipe.label, recipe.header, recipe.txt, recipe.item].join(' ').toLowerCase();
        return (state.craftCategory === 'all' || state.craftCategory === category) && (!search || text.indexOf(search) !== -1);
    });
}

function renderRequirements(requirements, isArcCraft) {
    return safeArray(requirements).map(function (requirement) {
        const owned = safeNumber(requirement && requirement.ownedAmount, 0);
        const amount = safeNumber(requirement && requirement.amount, 0);
        const isMet = requirement && requirement.isMet === true;
        return '' +
            '<div class="item-card__requirement ' + (isMet ? 'is-met' : 'is-missing') + '">' +
                '<strong>x' + esc(amount) + ' ' + esc((requirement && (requirement.itemLabel || requirement.item)) || 'Parça') + '</strong>' +
                '<span class="item-card__meta-label">' + esc((isArcCraft ? 'Depoda: ' : 'Sende: ') + owned + '/' + amount) + '</span>' +
            '</div>';
    }).join('');
}

function renderStageCard(stage, index, isArc) {
    const locked = stage && stage.locked === true;
    const multiplier = safeNumber(stage && stage.multiplier, 1);
    const recommended = Math.max(1, safeNumber(stage && stage.id, index + 1));
    const palette = [
        ['#162844', '#315f9f'],
        ['#14281f', '#2f7a54'],
        ['#2a1e16', '#94542f'],
        ['#25182b', '#8652d1']
    ][index % 4];
    const difficulty = isArc ? 'Sabit Konfigürasyon' : (multiplier >= 1.5 ? 'Yüksek Risk' : multiplier >= 1.2 ? 'Orta Risk' : 'Düşük Risk');

    const tag = locked ? 'article' : 'button';
    const attrs = locked ? '' : ' type="button" data-ui-action="select-stage" data-ui-payload="' + jsonAttr({ index: index }) + '"';
    return '' +
        '<' + tag + ' class="stage-card' + (locked ? ' is-locked' : '') + '"' + attrs + ' style="background:linear-gradient(135deg,' + palette[0] + ',' + palette[1] + ')">' +
            '<div class="stage-card__body">' +
                '<div class="stage-card__header">' +
                    '<span class="ui-badge ' + (locked ? 'ui-badge--warning' : 'ui-badge--muted') + '">' + esc(locked ? STRINGS.badge.locked : 'Hazır') + '</span>' +
                    '<span class="ui-badge ui-badge--muted">' + esc(isArc ? 'ARC' : ('x' + multiplier)) + '</span>' +
                '</div>' +
                '<div>' +
                    '<h3 class="stage-card__title">' + esc((stage && stage.label) || ('Stage ' + (index + 1))) + '</h3>' +
                    '<p class="ui-card__text">' + esc(locked ? ('Bu stage için önerilen seviye: ' + recommended) : (isArc ? 'ARC baskını sabit kurallarla başlar.' : 'Takımın hazırsa operasyona başlayabilirsin.')) + '</p>' +
                '</div>' +
                '<div class="stage-card__meta">' +
                    '<span class="ui-chip">' + esc(difficulty) + '</span>' +
                    '<span class="ui-chip">Önerilen Seviye: ' + esc(recommended) + '</span>' +
                '</div>' +
                '<div class="stage-card__action">' + esc(locked ? 'Kilit Açılmadı' : (isArc ? 'Baskını Başlat' : 'Operasyonu Başlat')) + '</div>' +
            '</div>' +
        '</' + tag + '>';
}

function getLobbyBadgeClass(lobby) {
    if (lobby && lobby.isOwnLobby) return 'ui-badge--primary';
    if (lobby && lobby.isJoinedLobby) return 'ui-badge--success';
    return 'ui-badge--muted';
}

function getLobbyBadgeText(lobby) {
    if (lobby && lobby.isOwnLobby) return 'Senin Lobin';
    if (lobby && lobby.isJoinedLobby) return 'Bağlı Olduğun Lobi';
    return 'Açık Lobi';
}

function getLockerUsage(section) {
    const slots = Math.max(1, safeNumber(section && section.slots, safeArray(section && section.items).length || 1));
    return clamp((safeArray(section && section.items).length / slots) * 100, 0, 100);
}

function getLockerCategory(item) {
    if (!item) return 'misc';
    if (item.isWeapon) return 'weapon';
    const text = [item.name, item.label, item.description].join(' ');
    const key = Object.keys(LOCKER_RULES).find(function (ruleKey) {
        return LOCKER_RULES[ruleKey].some(function (pattern) {
            return pattern.test(text);
        });
    });
    return key || 'misc';
}

function getLockerCategoryLabel(key) {
    const match = LOCKER_CATEGORIES.find(function (category) {
        return category.key === key;
    });
    return match ? match.label : STRINGS.lockerCategories.misc;
}

function renderLockerFilterChips() {
    return LOCKER_CATEGORIES.map(function (category) {
        return '<button class="ui-chip' + (state.lockerCategory === category.key ? ' is-active' : '') + '" type="button" data-ui-action="locker-category" data-ui-payload="' + jsonAttr({ category: category.key }) + '">' + esc(category.label) + '</button>';
    }).join('');
}

function renderLockerPanel(section, focusSide) {
    const items = safeArray(section && section.items).filter(function (item) {
        return state.lockerCategory === 'all' || getLockerCategory(item) === state.lockerCategory;
    });

    const placeholders = Math.max(0, Math.min(6, Math.max(safeNumber(section && section.slots, 0), items.length) - items.length));

    return '' +
        '<section class="locker-panel' + (section.side === focusSide ? ' is-focused' : '') + '">' +
            '<div class="locker-panel__header">' +
                '<div><p class="ui-overline">' + esc(section.side === 'loadout' ? 'Loadout' : 'Stash') + '</p><h3 class="locker-panel__title">' + esc(section.title || section.label) + '</h3><p class="ui-card__text">' + esc(section.helperText || '') + '</p></div>' +
                '<span class="ui-badge ' + (section.side === focusSide ? 'ui-badge--primary' : 'ui-badge--muted') + '">' + esc(section.side === focusSide ? STRINGS.badge.active : 'PASİF') + '</span>' +
            '</div>' +
            '<div class="locker-panel__summary">' +
                '<span class="ui-chip">' + esc(describeCount(safeArray(section.items).length, 'slot', 'slot')) + '</span>' +
                '<span class="ui-chip">Toplam Yuva: ' + esc(section.slots || safeArray(section.items).length) + '</span>' +
                '<span class="ui-chip">Filtre: ' + esc(getLockerCategoryLabel(state.lockerCategory)) + '</span>' +
            '</div>' +
            '<div class="locker-panel__grid" data-locker-drop-side="' + escAttr(section.side) + '">' +
                (items.length ? items.map(function (item) {
                    return renderLockerItem(section, item, focusSide);
                }).join('') : renderLockerPlaceholder(STRINGS.empty.locker)) +
                Array.from({ length: placeholders }).map(function () {
                    return renderLockerPlaceholder('Boş Slot');
                }).join('') +
            '</div>' +
        '</section>';
}

function renderLockerItem(section, item, focusSide) {
    const category = getLockerCategory(item);
    const toSide = section.side === 'loadout' ? 'main' : 'loadout';
    return '' +
        '<button class="locker-item" type="button" draggable="true" data-locker-side="' + escAttr(section.side) + '" data-locker-slot="' + escAttr(item.slot) + '">' +
            '<div class="locker-item__thumb">' +
                '<img src="' + escAttr(resolveItemImage(item)) + '" alt="' + escAttr(item.label) + '" data-fallback-src="' + escAttr(buildItemPlaceholder(item.label)) + '">' +
                '<span class="locker-item__count">x' + esc(item.count) + '</span>' +
            '</div>' +
            '<div class="locker-item__header">' +
                '<span class="locker-item__name">' + esc(item.label) + '</span>' +
                '<span class="ui-badge ui-badge--muted">#' + esc(item.slot) + '</span>' +
            '</div>' +
            '<div class="locker-item__meta">' + esc(getLockerCategoryLabel(category)) + ' · ' + esc(item.stackable ? 'Stacklenebilir' : 'Tekil') + '</div>' +
            '<div class="locker-item__actions">' +
                button('Taşı', 'locker-move', { fromSide: section.side, slot: item.slot, focusSide: focusSide, toSide: toSide }, 'ghost') +
                button('Ayır', 'locker-split-open', { fromSide: section.side, slot: item.slot }, 'ghost', !item.stackable || item.count <= 1) +
            '</div>' +
        '</button>';
}

function renderLockerPlaceholder(text) {
    return '<div class="locker-placeholder">' + esc(text) + '</div>';
}

function resolveItemImage(item) {
    const raw = safeString(item.image || (item.metadata && (item.metadata.imageurl || item.metadata.image)) || item.name);
    if (!raw) return buildItemPlaceholder(item.label || item.name);
    if (/^(https?:|data:|nui:|file:|\/|\.\/|\.\.\/)/i.test(raw) || raw.indexOf('cfx-nui-') !== -1) return raw;
    let image = raw.replace(/^images\//i, '');
    if (!/\.[a-z0-9]+$/i.test(image)) image += '.png';
    return 'https://cfx-nui-ox_inventory/web/images/' + image.split('/').map(encodeURIComponent).join('/');
}

function buildItemPlaceholder(label) {
    const initial = esc((safeString(label).trim().charAt(0) || '?').toUpperCase());
    const svg = '' +
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96">' +
            '<rect width="96" height="96" rx="18" fill="#142744"/>' +
            '<rect x="6" y="6" width="84" height="84" rx="16" fill="none" stroke="rgba(90,166,255,0.35)" stroke-width="2"/>' +
            '<text x="48" y="58" text-anchor="middle" font-size="38" font-family="Inter, sans-serif" fill="#d8e7ff">' + initial + '</text>' +
        '</svg>';
    return 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg);
}

function bindImageFallbacks(root) {
    if (!root) return;
    root.querySelectorAll('img[data-fallback-src]').forEach(function (image) {
        if (image.dataset.bound === '1') return;
        image.dataset.bound = '1';
        image.addEventListener('error', function () {
            if (image.dataset.failed === '1') return;
            image.dataset.failed = '1';
            image.src = image.getAttribute('data-fallback-src') || '';
        });
    });
}

function handleKeydown(event) {
    if (event.key !== 'Escape') return;
    if (state.confirmDialog) {
        state.confirmDialog = null;
        renderModal();
        return;
    }
    if (state.craftDialog) {
        state.craftDialog = null;
        renderModal();
        return;
    }
    if (state.arcLockers && state.arcLockers.splitDialog) {
        state.arcLockers.splitDialog = null;
        renderModal();
        return;
    }
    closeMenu();
}

function handleClick(event) {
    const target = event.target.closest('[data-ui-action]');
    if (!target) return;
    const action = safeString(target.getAttribute('data-ui-action'));
    const payload = parsePayload(target);
    dispatchAction(action, payload);
}

function handleInput(event) {
    const target = event.target;
    if (target.hasAttribute('data-craft-search')) {
        state.craftSearch = target.value || '';
        renderCurrentView();
        return;
    }

    if (target.id === 'craft-quantity-range' || target.id === 'craft-quantity-input') {
        syncCraftDialogAmount(target.value, target);
        return;
    }

    if (target.id === 'locker-split-range' || target.id === 'locker-split-input') {
        syncLockerSplitAmount(target.value, target);
    }
}

function dispatchAction(action, payload) {
    switch (action) {
        case 'noop':
            return;
        case 'close-menu':
            closeMenu();
            return;
        case 'go-back':
            sendAction('goBack', {});
            return;
        case 'toggle-ready':
            if (state.menuState.isMember) {
                state.menuState.isReady = !state.menuState.isReady;
                renderCurrentView();
                sendAction('toggleReady', {});
            }
            return;
        case 'open-market':
            sendAction('openMarket', {});
            return;
        case 'open-craft':
            sendAction('openCraft', {});
            return;
        case 'open-arc-craft':
            sendAction('openCraft', payload);
            return;
        case 'open-stages':
            sendAction('openStages', payload);
            return;
        case 'start-arc':
            sendAction('startArcPvP', {});
            return;
        case 'open-loadout-stash':
            sendAction('openArcLoadoutStash', {});
            return;
        case 'open-main-stash':
            sendAction('openArcMainStash', {});
            return;
        case 'open-members':
            sendAction('openMembers', {});
            return;
        case 'open-active-lobbies':
            sendAction('openActiveLobbies', {});
            return;
        case 'open-invite':
            sendAction('openInvite', {});
            return;
        case 'show-create-lobby':
            state.currentView = 'create-lobby';
            renderCurrentView();
            return;
        case 'create-lobby':
            state.menuState = Object.assign({}, state.menuState, {
                hasLobby: true,
                isLeader: true,
                isMember: false,
                isReady: false,
                lobbyStatus: payload.isPublic === true ? 'Herkese Açık Lider' : 'Özel Lider'
            });
            state.currentView = 'menu';
            renderCurrentView();
            sendAction('createLobby', { isPublic: payload.isPublic === true });
            return;
        case 'request-disband':
            openConfirmDialog('Lobiyi Dağıt', 'Lobiyi dağıtırsan tüm üyeler ekipten çıkarılır.', 'Lobiyi Dağıt', 'confirm-disband', payload, 'danger');
            return;
        case 'request-leave':
            openConfirmDialog('Lobiden Ayrıl', 'Lobiden ayrılırsan solo moda dönersin.', 'Lobiden Ayrıl', 'confirm-leave', payload, 'danger');
            return;
        case 'confirm-disband':
            state.confirmDialog = null;
            renderModal();
            sendAction('disbandLobby', {});
            return;
        case 'confirm-leave':
            state.confirmDialog = null;
            renderModal();
            sendAction('leaveLobby', {});
            return;
        case 'buy-upgrade': {
            const upgrade = state.upgrades[safeNumber(payload.index, -1)];
            if (!upgrade) return;
            openConfirmDialog('Satın Alma Onayı', (upgrade.label || 'Yükseltme') + ' için $' + formatCurrency(upgrade.price) + ' harcanacak.', 'Satın Al', 'confirm-buy-upgrade', { upgrade: upgrade }, 'primary');
            return;
        }
        case 'confirm-buy-upgrade':
            state.confirmDialog = null;
            renderModal();
            sendAction('buyUpgrade', payload.upgrade || {});
            return;
        case 'craft-category':
            state.craftCategory = safeString(payload.category, 'all');
            renderCurrentView();
            return;
        case 'craft-open':
            openCraftDialog(payload.index);
            return;
        case 'craft-confirm':
            confirmCraftDialog();
            return;
        case 'craft-cancel':
            state.craftDialog = null;
            renderModal();
            return;
        case 'select-stage': {
            const stage = state.stages[safeNumber(payload.index, -1)];
            if (!stage || stage.locked) return;
            sendAction('selectStage', { stageId: stage.id, modeId: state.selectedModeId || 'classic' });
            return;
        }
        case 'invite-player': {
            const player = state.players[safeNumber(payload.index, -1)];
            if (!player) return;
            sendAction('invitePlayer', { playerId: player.id });
            return;
        }
        case 'join-lobby-open': {
            const lobby = state.lobbies[safeNumber(payload.index, -1)];
            if (!lobby) return;
            openConfirmDialog('Lobiye Katıl', safeString(lobby.leaderName, 'Bu lobi') + ' liderliğindeki lobiye katılmak istiyor musun?', 'Katıl', 'confirm-join-lobby', { leaderId: lobby.leaderId }, 'primary');
            return;
        }
        case 'confirm-join-lobby':
            state.confirmDialog = null;
            renderModal();
            sendAction('joinPublicLobby', { leaderId: payload.leaderId });
            return;
        case 'accept-invite':
            sendAction('acceptInvite', { leaderId: state.inviteLeaderId });
            return;
        case 'deny-invite':
            sendAction('denyInvite', {});
            return;
        case 'reconnect-decision':
            sendAction('arcReconnectDecision', { accepted: payload.accepted === true });
            return;
        case 'refresh-lockers':
            sendAction('refreshArcLockers', payload);
            return;
        case 'swap-locker-focus':
            if (state.arcLockers) state.arcLockers.focusSide = payload.focusSide === 'loadout' ? 'loadout' : 'main';
            renderCurrentView();
            sendAction('swapArcLockerFocus', payload);
            return;
        case 'locker-category':
            state.lockerCategory = safeString(payload.category, 'all');
            renderCurrentView();
            return;
        case 'locker-move':
            sendAction('moveArcLockerItem', {
                fromSide: payload.fromSide,
                slot: payload.slot,
                focusSide: payload.focusSide || (state.arcLockers ? state.arcLockers.focusSide : 'main'),
                toSide: payload.toSide,
                targetSlot: payload.targetSlot,
                requestedAmount: payload.requestedAmount
            });
            return;
        case 'locker-split-open':
            openLockerSplitDialog(payload.fromSide, payload.slot);
            return;
        case 'locker-split-confirm':
            confirmLockerSplitDialog();
            return;
        case 'locker-split-cancel':
            if (state.arcLockers) state.arcLockers.splitDialog = null;
            renderModal();
            return;
        case 'confirm-cancel':
            state.confirmDialog = null;
            renderModal();
            return;
        default:
            console.warn('[gs-survival-ui] Unknown UI action:', action, payload);
    }
}

function openConfirmDialog(title, text, confirmLabel, confirmAction, payload, tone) {
    state.confirmDialog = {
        title: title,
        text: text,
        confirmLabel: confirmLabel,
        confirmAction: confirmAction,
        payload: payload || {},
        tone: tone || 'primary'
    };
    renderModal();
}

function openCraftDialog(index) {
    const recipe = state.recipes[safeNumber(index, -1)];
    if (!recipe) return;
    const maxCraftable = Math.max(0, safeNumber(recipe.maxCraftable, recipe.ready ? 1 : 0));
    if (maxCraftable < 1) {
        pushToast({
            type: 'warning',
            title: 'Üretim Başlatılamadı',
            message: 'Bu tarif için önce gerekli parçaları tamamlaman gerekiyor.',
            duration: 3200
        });
        return;
    }

    state.craftDialog = {
        index: safeNumber(index, 0),
        amount: clamp(Math.max(1, Math.round(maxCraftable * 0.5)), 1, maxCraftable),
        maxAmount: maxCraftable,
        outputAmount: Math.max(1, safeNumber(recipe.amount, 1)),
        label: recipe.label || recipe.header || 'Tarif'
    };
    renderModal();
}

function syncCraftDialogAmount(rawValue, source) {
    if (!state.craftDialog) return;
    state.craftDialog.amount = clamp(Math.floor(safeNumber(rawValue, state.craftDialog.amount)), 1, state.craftDialog.maxAmount);
    const range = document.getElementById('craft-quantity-range');
    const input = document.getElementById('craft-quantity-input');
    const count = document.getElementById('craft-quantity-count');
    const total = document.getElementById('craft-total-output');
    if (range && range !== source) range.value = String(state.craftDialog.amount);
    if (input && input !== source) input.value = String(state.craftDialog.amount);
    if (count) count.textContent = 'Üretim adedi: x' + state.craftDialog.amount;
    if (total) total.textContent = 'Toplam çıktı: x' + (state.craftDialog.amount * state.craftDialog.outputAmount);
}

function confirmCraftDialog() {
    if (!state.craftDialog) return;
    const dialog = state.craftDialog;
    const recipe = state.recipes[dialog.index];
    if (!recipe) return;
    state.craftDialog = null;
    renderModal();
    sendAction('craftItem', {
        item: recipe.item,
        amount: recipe.amount,
        label: recipe.label || recipe.header,
        multiplier: dialog.amount,
        stashId: recipe.stashId
    });
}

function openLockerSplitDialog(side, slot) {
    if (!state.arcLockers) return;
    const item = findLockerItem(side, slot);
    if (!item || item.count <= 1 || item.stackable === false || item.isWeapon) {
        pushToast({
            type: 'info',
            title: 'Yığın Ayrılamıyor',
            message: 'Sağ tıkla ayırma yalnızca stacklenebilen ve adedi 1’den büyük eşyalar için kullanılabilir.',
            duration: 3600
        });
        return;
    }

    const maxAmount = Math.max(1, item.count - 1);
    state.arcLockers.splitDialog = {
        fromSide: side === 'loadout' ? 'loadout' : 'main',
        targetSide: side === 'loadout' ? 'main' : 'loadout',
        slot: safeNumber(slot, 0),
        itemName: item.label,
        totalCount: item.count,
        maxAmount: maxAmount,
        amount: clamp(Math.round(maxAmount * 0.5), 1, maxAmount)
    };
    renderModal();
}

function syncLockerSplitAmount(rawValue, source) {
    const dialog = state.arcLockers && state.arcLockers.splitDialog;
    if (!dialog) return;
    dialog.amount = clamp(Math.floor(safeNumber(rawValue, dialog.amount)), 1, dialog.maxAmount);
    const range = document.getElementById('locker-split-range');
    const input = document.getElementById('locker-split-input');
    const sourceCount = document.getElementById('locker-split-source-count');
    const targetCount = document.getElementById('locker-split-target-count');
    if (range && range !== source) range.value = String(dialog.amount);
    if (input && input !== source) input.value = String(dialog.amount);
    if (sourceCount) sourceCount.textContent = 'Kaynakta kalacak: x' + Math.max(dialog.totalCount - dialog.amount, 0);
    if (targetCount) targetCount.textContent = 'Taşınacak: x' + dialog.amount;
}

function confirmLockerSplitDialog() {
    const dialog = state.arcLockers && state.arcLockers.splitDialog;
    if (!dialog || !state.arcLockers) return;
    state.arcLockers.splitDialog = null;
    renderModal();
    sendAction('moveArcLockerItem', {
        fromSide: dialog.fromSide,
        slot: dialog.slot,
        focusSide: state.arcLockers.focusSide,
        toSide: dialog.targetSide,
        targetSlot: null,
        requestedAmount: dialog.amount
    });
}

function findLockerItem(side, slot) {
    if (!state.arcLockers) return null;
    const section = side === 'loadout' ? state.arcLockers.loadout : state.arcLockers.main;
    return safeArray(section && section.items).find(function (item) {
        return Number(item.slot) === Number(slot);
    }) || null;
}

function renderModal() {
    let html = '';
    if (state.craftDialog) html = renderCraftDialog();
    else if (state.arcLockers && state.arcLockers.splitDialog) html = renderLockerSplitDialog();
    else if (state.confirmDialog) html = renderConfirmDialog();

    ui.modalRoot.innerHTML = html;
    ui.modalRoot.classList.toggle('hidden', !html);
    ui.modalRoot.setAttribute('aria-hidden', html ? 'false' : 'true');
}

function renderConfirmDialog() {
    const dialog = state.confirmDialog || {};
    return '' +
        '<article class="modal" role="dialog" aria-modal="true">' +
            '<div class="modal__header">' +
                '<div><p class="ui-overline">Onay</p><h3 class="modal__title">' + esc(dialog.title || 'Emin misin?') + '</h3></div>' +
                '<span class="ui-badge ' + (dialog.tone === 'danger' ? 'ui-badge--danger' : 'ui-badge--primary') + '">Onay</span>' +
            '</div>' +
            '<div class="modal__content"><p class="modal__text">' + esc(dialog.text || '') + '</p></div>' +
            '<div class="modal__actions">' +
                button('Vazgeç', 'confirm-cancel', {}, 'ghost') +
                button(dialog.confirmLabel || 'Onayla', dialog.confirmAction || 'noop', dialog.payload || {}, dialog.tone === 'danger' ? 'danger' : 'primary') +
            '</div>' +
        '</article>';
}

function renderCraftDialog() {
    const dialog = state.craftDialog;
    return '' +
        '<article class="modal" role="dialog" aria-modal="true">' +
            '<div class="modal__header">' +
                '<div><p class="ui-overline">Üretim</p><h3 class="modal__title">' + esc(dialog.label) + '</h3></div>' +
                '<span class="ui-badge ui-badge--primary">x' + esc(dialog.outputAmount) + ' çıktı</span>' +
            '</div>' +
            '<div class="modal__content">' +
                '<p class="modal__text">Bu tariften şu an en fazla ' + esc(dialog.maxAmount) + ' kez üretebilirsin.</p>' +
                '<div class="dialog-stats">' +
                    '<div class="dialog-stats__item"><span class="status-grid__label">Maksimum</span><strong class="status-grid__value">x' + esc(dialog.maxAmount) + '</strong></div>' +
                    '<div class="dialog-stats__item"><span class="status-grid__label">Toplam Çıktı</span><strong id="craft-total-output" class="status-grid__value">x' + esc(dialog.amount * dialog.outputAmount) + '</strong></div>' +
                '</div>' +
                '<input id="craft-quantity-range" class="ui-range" type="range" min="1" max="' + escAttr(dialog.maxAmount) + '" value="' + escAttr(dialog.amount) + '">' +
                '<input id="craft-quantity-input" class="ui-number" type="number" min="1" max="' + escAttr(dialog.maxAmount) + '" value="' + escAttr(dialog.amount) + '">' +
                '<div id="craft-quantity-count" class="ui-card__text">Üretim adedi: x' + esc(dialog.amount) + '</div>' +
            '</div>' +
            '<div class="modal__actions">' +
                button('İptal', 'craft-cancel', {}, 'ghost') +
                button('Üretimi Başlat', 'craft-confirm', {}, 'primary') +
            '</div>' +
        '</article>';
}

function renderLockerSplitDialog() {
    const dialog = state.arcLockers.splitDialog;
    return '' +
        '<article class="modal" role="dialog" aria-modal="true">' +
            '<div class="modal__header">' +
                '<div><p class="ui-overline">Yığın Ayır</p><h3 class="modal__title">' + esc(dialog.itemName) + '</h3></div>' +
                '<span class="ui-badge ui-badge--warning">Split</span>' +
            '</div>' +
            '<div class="modal__content">' +
                '<p class="modal__text">Bu yığından kaç adet ' + esc(dialog.targetSide === 'loadout' ? 'Baskın Çantası' : 'Kalıcı Depo') + ' tarafına taşınsın?</p>' +
                '<div class="dialog-stats">' +
                    '<div class="dialog-stats__item"><span class="status-grid__label">Toplam</span><strong class="status-grid__value">x' + esc(dialog.totalCount) + '</strong></div>' +
                    '<div class="dialog-stats__item"><span class="status-grid__label">Taşınacak</span><strong id="locker-split-target-count" class="status-grid__value">x' + esc(dialog.amount) + '</strong></div>' +
                    '<div class="dialog-stats__item"><span class="status-grid__label">Kaynakta Kalacak</span><strong id="locker-split-source-count" class="status-grid__value">x' + esc(Math.max(dialog.totalCount - dialog.amount, 0)) + '</strong></div>' +
                '</div>' +
                '<input id="locker-split-range" class="ui-range" type="range" min="1" max="' + escAttr(dialog.maxAmount) + '" value="' + escAttr(dialog.amount) + '">' +
                '<input id="locker-split-input" class="ui-number" type="number" min="1" max="' + escAttr(dialog.maxAmount) + '" value="' + escAttr(dialog.amount) + '">' +
            '</div>' +
            '<div class="modal__actions">' +
                button('İptal', 'locker-split-cancel', {}, 'ghost') +
                button('Ayır ve Taşı', 'locker-split-confirm', {}, 'primary') +
            '</div>' +
        '</article>';
}

function handleDragStart(event) {
    const card = event.target.closest('.locker-item');
    if (!card) return;
    const payload = {
        fromSide: card.getAttribute('data-locker-side'),
        slot: Number(card.getAttribute('data-locker-slot')) || 0
    };
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', JSON.stringify(payload));
}

function handleDragOver(event) {
    const target = event.target.closest('[data-locker-drop-side], .locker-item');
    if (!target) return;
    event.preventDefault();
    clearDropTargets();
    target.classList.add('is-drop-target');
}

function handleDragLeave(event) {
    const target = event.target.closest('.is-drop-target');
    if (!target) return;
    if (event.relatedTarget && target.contains(event.relatedTarget)) return;
    target.classList.remove('is-drop-target');
}

function handleDrop(event) {
    const targetItem = event.target.closest('.locker-item');
    const targetPanel = event.target.closest('[data-locker-drop-side]');
    if (!targetItem && !targetPanel) return;
    event.preventDefault();
    clearDropTargets();

    const raw = event.dataTransfer.getData('text/plain');
    if (!raw || !state.arcLockers) return;

    let payload = null;
    try {
        payload = JSON.parse(raw);
    } catch (error) {
        console.warn('[gs-survival-ui] Invalid drag payload:', error);
        return;
    }

    if (!payload || !payload.fromSide || !payload.slot) return;

    sendAction('moveArcLockerItem', {
        fromSide: payload.fromSide,
        slot: payload.slot,
        focusSide: state.arcLockers.focusSide,
        toSide: targetItem ? targetItem.getAttribute('data-locker-side') : targetPanel.getAttribute('data-locker-drop-side'),
        targetSlot: targetItem ? Number(targetItem.getAttribute('data-locker-slot')) || null : null,
        requestedAmount: null
    });
}

function handleContextMenu(event) {
    const card = event.target.closest('.locker-item');
    if (!card) return;
    event.preventDefault();
    openLockerSplitDialog(card.getAttribute('data-locker-side'), card.getAttribute('data-locker-slot'));
}

function clearDropTargets() {
    document.querySelectorAll('.is-drop-target').forEach(function (element) {
        element.classList.remove('is-drop-target');
    });
}

function splitArcLine(text) {
    const value = safeString(text).trim();
    const separator = value.indexOf(':');
    if (separator === -1) return { label: 'ARC', value: value || '-' };
    return {
        label: value.slice(0, separator).trim() || 'ARC',
        value: value.slice(separator + 1).trim() || '-'
    };
}

function getTeamStatus(member) {
    if (member && member.isSelf) return STRINGS.teamStatus.self;
    if (member && member.isAlive === false) return STRINGS.teamStatus.down;
    return STRINGS.teamStatus.online;
}

function renderOverlays() {
    renderBanner();
    renderProgress();
    renderBarricade();
    renderArcInfo();
    renderArcTeam();
    syncOverlayVisibility();
}

function renderBanner() {
    const banner = state.arcBanner;
    const visible = banner.visible === true && safeString(banner.title).trim().length > 0;
    ui.banner.classList.toggle('hidden', !visible);
    ui.bannerLabel.textContent = banner.label || STRINGS.banner.label;
    ui.bannerTitle.textContent = banner.title || STRINGS.banner.title;
}

function renderProgress() {
    const progress = state.arcProgress;
    ui.progressCard.classList.toggle('hidden', progress.visible !== true);
    ui.progressTitle.textContent = progress.title || STRINGS.progress.title;
    ui.progressLabel.textContent = progress.label || STRINGS.progress.label;
    ui.progressCancel.textContent = progress.canCancel === false ? STRINGS.progress.locked : STRINGS.progress.cancel;
    updateProgressVisuals(Date.now());
}

function renderBarricade() {
    const card = state.arcBarricadePlacement;
    ui.barricadeCard.classList.toggle('hidden', card.visible !== true);
    ui.barricadeTitle.textContent = card.title || STRINGS.barricade.title;
    ui.barricadeControls.innerHTML = safeArray(card.controls).map(function (control) {
        return '<div class="overlay-placement__control"><span>' + esc(control.key || '-') + '</span><strong>' + esc(control.action || '') + '</strong></div>';
    }).join('');
}

function renderArcInfo() {
    const hud = state.arcHud;
    const lines = safeArray(hud.lines);
    const hasPrompt = safeString(hud.prompt).trim().length > 0;
    const visible = hud.enabled === true && hud.showInfo === true && (safeString(hud.title).trim() || safeString(hud.subtitle).trim() || lines.length > 0 || hasPrompt);
    ui.infoPanel.classList.toggle('hidden', !visible);
    ui.infoTitle.textContent = hud.title || 'ARC Operasyonu';
    ui.infoSubtitle.textContent = hud.subtitle || 'Saha telemetrisi';
    ui.infoLines.innerHTML = lines.map(function (line) {
        const parsed = splitArcLine(line);
        return '<div class="overlay-panel__line"><span>' + esc(parsed.label) + '</span><strong>' + esc(parsed.value) + '</strong></div>';
    }).join('');
    ui.infoPrompt.textContent = hud.prompt || '';
    ui.infoPrompt.classList.toggle('hidden', !hasPrompt);
}

function renderArcTeam() {
    const members = safeArray(state.arcHud.teamMembers);
    const visible = state.arcHud.enabled === true && members.length > 0;
    ui.teamPanel.classList.toggle('hidden', !visible);
    ui.teamCount.textContent = describeCount(members.length, 'üye', 'üye').toUpperCase();
    ui.teamMembers.innerHTML = members.map(function (member) {
        const status = getTeamStatus(member);
        const classes = ['overlay-team__member'];
        if (status === STRINGS.teamStatus.self) classes.push('is-self');
        if (status === STRINGS.teamStatus.down) classes.push('is-down');
        return '<div class="' + classes.join(' ') + '"><span>' + esc(member.name || 'Bilinmeyen Operatör') + '</span><strong>' + esc(status.badge) + '</strong></div>';
    }).join('');
}

function syncOverlayVisibility() {
    const hasToasts = ui.notifyStack.children.length > 0;
    const visible = !ui.banner.classList.contains('hidden') ||
        !ui.progressCard.classList.contains('hidden') ||
        !ui.barricadeCard.classList.contains('hidden') ||
        !ui.infoPanel.classList.contains('hidden') ||
        !ui.teamPanel.classList.contains('hidden') ||
        hasToasts;
    ui.overlayRoot.classList.toggle('hidden', !visible);
    ui.overlayRoot.setAttribute('aria-hidden', visible ? 'false' : 'true');
}

function normalizeNotifyType(type) {
    const value = safeString(type, 'info').toLowerCase();
    return STRINGS.notifyTitle[value] ? value : 'info';
}

function pushToast(data) {
    const type = normalizeNotifyType(data.type);
    const title = safeString(data.title, STRINGS.notifyTitle[type]);
    const message = safeString(data.message, '');
    const toast = document.createElement('div');
    toast.className = 'overlay-toast overlay-toast--' + type;
    toast.innerHTML = '<div class="overlay-toast__title">' + esc(title) + '</div><div class="overlay-toast__message">' + esc(message) + '</div>';
    ui.notifyStack.appendChild(toast);
    syncOverlayVisibility();

    const timeout = setTimeout(function () {
        notifyTimers = notifyTimers.filter(function (id) {
            return id !== timeout;
        });
        toast.classList.add('is-leaving');
        setTimeout(function () {
            if (toast.parentNode) toast.parentNode.removeChild(toast);
            syncOverlayVisibility();
        }, 300);
    }, clamp(safeNumber(data.duration, LIMITS.notifyDefault), LIMITS.notifyMin, LIMITS.notifyMax));

    notifyTimers.push(timeout);
}

function showBanner(data) {
    clearBanner(true);
    state.arcBanner = {
        visible: true,
        label: safeString(data.label, STRINGS.banner.label),
        title: safeString(data.title, STRINGS.banner.title),
        duration: clamp(safeNumber(data.duration, LIMITS.bannerDefault), LIMITS.bannerMin, LIMITS.bannerMax),
        transition: data.transition === true
    };
    renderOverlays();
    bannerTimer = setTimeout(function () {
        clearBanner();
    }, state.arcBanner.duration);
}

function clearBanner(skipRender) {
    clearTimeout(bannerTimer);
    bannerTimer = null;
    state.arcBanner = getDefaultArcBannerState();
    if (!skipRender) renderOverlays();
}

function showProgress(data) {
    cancelAnimationFrame(progressFrame);
    state.arcProgress = {
        visible: true,
        id: safeNumber(data.id, 0),
        title: safeString(data.title, STRINGS.progress.title),
        label: safeString(data.label, STRINGS.progress.label),
        duration: clamp(safeNumber(data.duration, LIMITS.progressMin), LIMITS.progressMin, LIMITS.progressMax),
        canCancel: data.canCancel !== false,
        startedAt: Date.now(),
        completedNotified: false
    };
    renderOverlays();
    tickProgress();
}

function clearProgress() {
    cancelAnimationFrame(progressFrame);
    progressFrame = null;
    state.arcProgress = getDefaultArcProgressState();
    renderOverlays();
}

function updateProgressVisuals(now) {
    const progress = state.arcProgress;
    let percent = 0;
    if (progress.visible === true && progress.duration > 0) {
        percent = clamp(((now - progress.startedAt) / progress.duration) * 100, 0, 100);
    }
    ui.progressFill.style.width = percent + '%';
    ui.progressPercent.textContent = Math.round(percent) + '%';
}

function tickProgress() {
    cancelAnimationFrame(progressFrame);
    updateProgressVisuals(Date.now());
    if (state.arcProgress.visible !== true) return;
    if ((Date.now() - state.arcProgress.startedAt) < state.arcProgress.duration) {
        progressFrame = requestAnimationFrame(tickProgress);
        return;
    }
    if (state.arcProgress.completedNotified !== true) {
        state.arcProgress.completedNotified = true;
        sendAction('arcProgressComplete', { id: state.arcProgress.id });
    }
}

function clearArcHudState() {
    state.arcHud = getDefaultArcHudState();
    state.arcBarricadePlacement = getDefaultArcBarricadeState();
    state.arcProgress = getDefaultArcProgressState();
    clearBanner(true);
    cancelAnimationFrame(progressFrame);
    progressFrame = null;
    notifyTimers.forEach(clearTimeout);
    notifyTimers = [];
    ui.notifyStack.innerHTML = '';
    renderOverlays();
}
