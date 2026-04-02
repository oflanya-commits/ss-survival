'use strict';

var MAX_LOBBY_SIZE = 4;
var ARC_HUD_DEFAULTS = {
    title: 'ARC Operasyonu',
    subtitle: 'Saha telemetrisi'
};
var ARC_TEAM_COUNT_TEXT = 'ÜYE';
var ARC_TEAM_STATUS = {
    self: {
        text: 'Sen',
        badge: 'SEN'
    },
    down: {
        text: 'Bağlantı Kesildi',
        badge: 'KESİK'
    },
    online: {
        text: 'Takım Arkadaşı',
        badge: 'ONLINE'
    }
};
var ARC_NOTIFY_DEFAULT_DURATION = 7000;
var ARC_NOTIFY_MIN_DURATION = 4500;
var ARC_NOTIFY_MAX_DURATION = 18000;
var ARC_NOTIFY_EXIT_DURATION_MS = 300;
var ARC_BARRICADE_DEFAULT_BOTTOM_OFFSET = 34;
var ARC_BARRICADE_TEAM_PANEL_GAP = 18;
var ARC_TEAM_PANEL_BOTTOM_OFFSET = 22;
var ARC_BANNER_DEFAULT_DURATION = 3200;
var ARC_BANNER_MIN_DURATION = 1200;
var ARC_BANNER_MAX_DURATION = 8000;
var ARC_BANNER_DEFAULT_LABEL = 'ARC TAHLİYE';
var ARC_BANNER_DEFAULT_TITLE = 'LOBİYE DÖNÜLÜYOR';
var ARC_PROGRESS_DEFAULT_TITLE = 'Operasyon Sürüyor';
var ARC_PROGRESS_DEFAULT_LABEL = 'Lütfen bekle...';
var ARC_PROGRESS_CANCEL_ENABLED_TEXT = 'ESC ile iptal edebilirsin';
var ARC_PROGRESS_CANCEL_DISABLED_TEXT = 'İptal devre dışı';
var ARC_PROGRESS_MIN_DURATION = 250;
var ARC_PROGRESS_MAX_DURATION = 60000;
var ARC_NOTIFY_TYPES = {
    info: true,
    success: true,
    error: true,
    warning: true,
    primary: true
};

function getDefaultArcProgressState() {
    return {
        visible: false,
        id: 0,
        title: ARC_PROGRESS_DEFAULT_TITLE,
        label: ARC_PROGRESS_DEFAULT_LABEL,
        duration: 0,
        canCancel: true,
        startedAt: 0,
        completedNotified: false
    };
}

function getDefaultArcBarricadePlacementState() {
    return {
        visible: false,
        title: 'ARC Barricade Kit',
        controls: []
    };
}

// ─── Per-screen data store (avoids inline JSON injection) ──────────────────
var screenData = {
    upgrades: [],
    recipes:  [],
    craftSource: null,
    craftDialog: null,
    stages:   [],
    players:  [],
    lobbies:  [],
    members:  [],
    arcLockers: null,
    inviteLeaderId: null,
    memberLeaderId: null,
    reconnectPrompt: null,
    menuState: {},
    menuView: null,
    menuSelections: {
        arcZoneId: null,
        survivalStageId: null
    },
    arcHud: {
        enabled: false,
        showInfo: false,
        title: ARC_HUD_DEFAULTS.title,
        subtitle: ARC_HUD_DEFAULTS.subtitle,
        lines: [],
        prompt: '',
        teamMembers: []
    },
    arcBanner: {
        visible: false,
        label: ARC_BANNER_DEFAULT_LABEL,
        title: ARC_BANNER_DEFAULT_TITLE,
        duration: ARC_BANNER_DEFAULT_DURATION,
        transition: false
    },
    arcProgress: getDefaultArcProgressState()
    ,
    arcBarricadePlacement: getDefaultArcBarricadePlacementState()
};

// ─── Cached nodes for HUD, tooltip, and menu transitions ───────────────────
var appEl = document.getElementById('app');
var contentEl = document.getElementById('content');
var tooltipEl = document.getElementById('hud-tooltip');
var hudEls = {
    menuSidebarShell: document.getElementById('menu-sidebar-shell'),
    menuSidebar: document.getElementById('menu-sidebar'),
    statusTitle: document.getElementById('status-strip-title'),
    healthLabel: document.getElementById('hud-health-label'),
    healthValue: document.getElementById('hud-health-value'),
    healthBar: document.getElementById('hud-health-bar'),
    radiationLabel: document.getElementById('hud-radiation-label'),
    radiationValue: document.getElementById('hud-radiation-value'),
    radiationBar: document.getElementById('hud-radiation-bar'),
    inventoryLabel: document.getElementById('hud-inventory-label'),
    inventoryValue: document.getElementById('hud-inventory-value'),
    inventoryBar: document.getElementById('hud-inventory-bar'),
    signalLabel: document.getElementById('hud-signal-label'),
    signalValue: document.getElementById('hud-signal-value'),
    signalBar: document.getElementById('hud-signal-bar'),
    lobbyMembersPanel: document.getElementById('lobby-members-panel'),
    lobbyMembersList: document.getElementById('lobby-members-list'),
    missionBrief: document.getElementById('mission-brief'),
    briefTitle: document.getElementById('brief-title'),
    briefText: document.getElementById('brief-text'),
    briefExtraction: document.getElementById('brief-extraction'),
    briefExtractionPhase: document.getElementById('brief-extraction-phase'),
    briefExtractionObjective: document.getElementById('brief-extraction-objective'),
    briefExtractionCountdown: document.getElementById('brief-extraction-countdown'),
    briefTag: document.getElementById('brief-tag'),
    briefProgress: document.getElementById('brief-progress-bar'),
    arcOverlayRoot: document.getElementById('arc-overlay-root'),
    arcInfoPanel: document.getElementById('arc-info-panel'),
    arcInfoTitle: document.getElementById('arc-info-title'),
    arcInfoSubtitle: document.getElementById('arc-info-subtitle'),
    arcInfoLines: document.getElementById('arc-info-lines'),
    arcInfoPrompt: document.getElementById('arc-info-prompt'),
    arcTeamPanel: document.getElementById('arc-team-panel'),
    arcTeamCount: document.getElementById('arc-team-count'),
    arcTeamMembers: document.getElementById('arc-team-members'),
    arcNotifyStack: document.getElementById('arc-notify-stack'),
    arcResultBanner: document.getElementById('arc-result-banner'),
    arcResultBannerLabel: document.getElementById('arc-result-banner-label'),
    arcResultBannerTitle: document.getElementById('arc-result-banner-title'),
    arcProgressCard: document.getElementById('arc-progress-card'),
    arcProgressTitle: document.getElementById('arc-progress-title'),
    arcProgressLabel: document.getElementById('arc-progress-label'),
    arcProgressFill: document.getElementById('arc-progress-fill'),
    arcProgressPercent: document.getElementById('arc-progress-percent'),
    arcProgressCancel: document.getElementById('arc-progress-cancel'),
    arcBarricadePlacementCard: document.getElementById('arc-barricade-placement-card'),
    arcBarricadePlacementTitle: document.getElementById('arc-barricade-placement-title'),
    arcBarricadePlacementControls: document.getElementById('arc-barricade-placement-controls')
};
var audioCtx = null;
var currentScreen = 'menu';
var arcNotifyTimers = [];
var arcBannerTimer = null;
var arcProgressFrame = null;
var DEFAULT_HUD = {
    health: 84,
    radiation: 22,
    inventoryPct: 50,
    inventoryText: '03/06',
    signal: 68,
    signalText: 'STABIL',
    briefTitle: 'Operasyon Hazır',
    briefText: 'Takım durumunu kontrol et, bölgeyi seç ve ekipmanını hazırla.',
    briefExtractionPhase: '',
    briefExtractionObjective: '',
    briefExtractionCountdown: '',
    briefTag: 'BEKLE',
    progress: 28,
    slotsFilled: 3
};
var MAIN_MENU_BASE_HEALTH = 62;
var MAIN_MENU_HEALTH_PER_LEVEL = 3;
var ARC_LOCKER_CATEGORIES = [
    { key: 'all', label: 'Tümü', icon: '&#9638;' },
    { key: 'weapon', label: 'Silah', icon: '&#128299;' },
    { key: 'ammo', label: 'Mermi', icon: '&#9903;' },
    { key: 'medical', label: 'Medikal', icon: '&#10010;' },
    { key: 'food', label: 'Gıda', icon: '&#127860;' },
    { key: 'utility', label: 'Ekipman', icon: '&#128295;' },
    { key: 'misc', label: 'Diğer', icon: '&#128230;' }
];
var ARC_LOCKER_CATEGORY_RULES = {
    ammo: [/(ammo|bullet|9mm|5\.56|7\.62|12g|shell|mermi)/],
    medical: [/(med|bandage|first aid|painkiller|adrenaline|syringe|health|burn cream|cream)/],
    food: [/(water|cola|drink|food|sandwich|bread|burger|milk|juice|consume)/],
    utility: [/(tool|lockpick|radio|phone|repair kit|repairkit|armor|z[ıi]rh|helmet|bag|utility)/]
};
var MENU_NAV_ITEMS = [
    {
        key: 'arc',
        label: 'ARC MODU',
        meta: 'Baskın Merkezi',
        panels: [
            { key: 'arcRaid', label: 'ARC BASKINI', desc: 'Baskın bölgesini seç ve operasyona hazırlan.' },
            { key: 'arcLoadout', label: 'BASKIN ÇANTASI', desc: 'Üstüne verilecek ekipmanı düzenle.' },
            { key: 'arcWorkshop', label: 'ARC ATÖLYESİ', desc: 'Kalıcı depodaki malzemelerle üretim yap.' },
            { key: 'arcDepot', label: 'KALICI DEPO', desc: 'Baskın dışında da sende kalan depoyu yönet.' }
        ]
    },
    {
        key: 'survival',
        label: 'HAYATTA KALMA MODU',
        meta: 'Dalga Operasyonu',
        panels: [
            { key: 'survivalRaid', label: 'HAYATTA KALMA', desc: 'Haritayı seç, sonra sol alttan başlat.' },
            { key: 'survivalMarket', label: 'MARKET', desc: 'Saha güçlendirmelerini kredi ile aç.' },
            { key: 'survivalWorkshop', label: 'ATÖLYE', desc: 'Topladığın malzemelerle ekipman üret.' }
        ]
    },
    {
        key: 'lobby',
        label: 'LOBİ',
        meta: 'Takım Sistemi',
        panels: [
            { key: 'lobbySettings', label: 'LOBİ AYARLARI', desc: 'Takım, hazır durumu ve davet akışını yönet.' }
        ]
    }
];
// Drag sonrası istemsiz click tetiklenmesini önlemek için kısa bastırma süreleri kullanılır.
var ARC_LOCKER_DRAG_SUPPRESS_START_MS = 250;
var ARC_LOCKER_DRAG_SUPPRESS_DROP_MS = 350;
var ARC_LOCKER_DRAG_SUPPRESS_END_MS = 150;
var ARC_LOCKER_POINTER_DRAG_THRESHOLD_PX = 8;
var ARC_LOCKER_POINTER_DRAG_THRESHOLD_SQ = ARC_LOCKER_POINTER_DRAG_THRESHOLD_PX * ARC_LOCKER_POINTER_DRAG_THRESHOLD_PX;
var ARC_LOCKER_DEFAULT_SPLIT_RATIO = 0.5;
var arcLockerDragState = null;
var arcLockerDragSuppressUntil = 0;
var arcLockerNativeDragActive = false;
var arcLockerPointerDragState = null;

// ─── NUI Message Handler ───────────────────────────────────────────────────
window.addEventListener('message', function (event) {
    var d = event.data;
    switch (d.type) {
        case 'openMenu':      showMenu(d.data);         showApp(); break;
        case 'openMarket':    showMarket(d.data);                  break;
        case 'openCraft':     showCraft(d.data); showApp();        break;
        case 'openStages':    showStages(d.data);                  break;
        case 'openArcLockers': showArcLockers(d.data); showApp();  break;
        case 'openInvite':    showInvite(d.data);                  break;
        case 'openActiveLobbies': showActiveLobbies(d.data);       break;
        case 'openMembers':   showMembers(d.data);                 break;
        case 'syncLobbyMembers': syncLobbyMembers(d.data);         break;
        case 'updateMenuState':  updateMenuState(d.data);          break;
        case 'setArcHud':     setArcHud(d.data);                   break;
        case 'clearArcHud':   clearArcHud();                       break;
        case 'arcNotify':     pushArcNotify(d.data);               break;
        case 'showArcBanner': showArcBanner(d.data);              break;
        case 'clearArcBanner': clearArcBanner();                  break;
        case 'showArcProgress': showArcProgress(d.data);          break;
        case 'hideArcProgress': clearArcProgress();               break;
        case 'showArcBarricadePlacement': showArcBarricadePlacement(d.data); break;
        case 'hideArcBarricadePlacement': clearArcBarricadePlacement(); break;
        case 'openReconnectPrompt': showReconnectPrompt(d.data); showApp(); break;
        case 'receiveInvite': showReceiveInvite(d.data); showApp(); break;
        case 'closeMenu':     hideApp();                           break;
    }
});

// ─── ESC closes menu ──────────────────────────────────────────────────────
document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && currentScreen === 'arcLockers' && screenData.arcLockers && screenData.arcLockers.splitDialog) {
        closeArcLockerSplitDialog();
        return;
    }
    if (e.key === 'Escape' && currentScreen === 'craft' && screenData.craftDialog) {
        closeCraftQuantityDialog();
        return;
    }
    if (e.key === 'Escape' && currentScreen === 'arc-reconnect') {
        submitArcReconnectDecision(false);
        return;
    }
    if (e.key === 'Escape') closeMenu();
});

// ─── UI click + hover feedback ─────────────────────────────────────────────
document.addEventListener('click', function (event) {
    var target = event.target.closest('.btn, .menu-item, .player-item, .stage-card, .menu-sidebar-main, .menu-sidebar-subitem, .menu-choice-card');
    if (target && !target.classList.contains('disabled') && !target.disabled) {
        // Ready/craft actions play their own mechanical sounds from their dedicated handlers.
        if (target.classList.contains('pubg-ready-btn') || target.classList.contains('btn-craft-action')) return;
        playUiTone(target.classList.contains('btn-danger') || target.classList.contains('danger') ? 'alert' : 'confirm');
    }
});

document.addEventListener('click', function (event) {
    if (Date.now() < arcLockerDragSuppressUntil && event.target.closest('.arc-item-card')) {
        event.preventDefault();
        event.stopPropagation();
    }
}, true);

document.addEventListener('mouseover', function (event) {
    var target = event.target.closest('[data-tip]');
    if (!target || target.classList.contains('disabled')) {
        hideTooltip();
        return;
    }
    showTooltip(target.getAttribute('data-tip'));
});

document.addEventListener('mousemove', function (event) {
    if (tooltipEl.classList.contains('hidden')) return;
    tooltipEl.style.left = event.clientX + 'px';
    tooltipEl.style.top = event.clientY + 'px';
});

document.addEventListener('mouseout', function (event) {
    if (!event.target.closest('[data-tip]')) return;
    if (event.relatedTarget && event.relatedTarget.closest('[data-tip]')) return;
    hideTooltip();
});

document.addEventListener('mouseleave', function () {
    hideTooltip();
});

// ─── Visibility ───────────────────────────────────────────────────────────
function showApp() {
    appEl.classList.remove('hidden');
    appEl.setAttribute('aria-hidden', 'false');
    requestAnimationFrame(function () {
        appEl.classList.add('is-visible');
    });
}

function hideApp() {
    appEl.classList.remove('is-visible');
    appEl.setAttribute('aria-hidden', 'true');
    hideTooltip();
    appEl.classList.add('hidden');
}

// ─── Close menu (tell Lua to release focus) ───────────────────────────────
function closeMenu() {
    if (currentScreen === 'arc-reconnect') {
        submitArcReconnectDecision(false);
        return;
    }
    hideApp();
    sendAction('closeMenu', {});
}

// ─── Lua callback ─────────────────────────────────────────────────────────
function sendAction(action, data) {
    fetch('https://' + GetParentResourceName() + '/nuiAction', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: action, data: data })
    }).catch(function () {});
}

// ─── Breadcrumb ───────────────────────────────────────────────────────────
function setBreadcrumb(text) {
    document.getElementById('breadcrumb-text').textContent = text;
}

// ─── Helper: menu row ─────────────────────────────────────────────────────
function menuRow(icon, title, desc, badgeHtml, onclickJs, extraClass, tipText) {
    var cls = 'menu-item' + (extraClass ? ' ' + extraClass : '');
    var clickAttr = onclickJs ? ' onclick="' + onclickJs + '"' : '';
    var arrowHtml = (extraClass !== 'disabled') ? '<div class="menu-arrow">&#8250;</div>' : '';
    var tipAttr = tipText ? ' data-tip="' + esc(tipText) + '"' : '';
    return '<div class="' + cls + '"' + clickAttr + tipAttr + '>' +
        '<div class="menu-item-icon">' + icon + '</div>' +
        '<div class="menu-item-content">' +
            '<div class="menu-item-title">' + esc(title) + '</div>' +
            (desc ? '<div class="menu-item-desc">' + esc(desc) + '</div>' : '') +
        '</div>' +
        (badgeHtml || '') +
        arrowHtml +
    '</div>';
}

function backBtn() {
    return '<button class="btn btn-back" type="button" onclick="goBackToMainMenu()" data-tip="Ana ekrana geri dön.">&#8592; Ana Menüye Dön</button>';
}

function actionBtn(label, action, data, tipText, extraClass) {
    var payload = JSON.stringify(data || {}).replace(/"/g, '&quot;');
    return '<button class="btn' + (extraClass ? ' ' + extraClass : '') + '" type="button" onclick="sendAction(\'' + esc(action) + '\',' + payload + ')"' +
        (tipText ? ' data-tip="' + esc(tipText) + '"' : '') + '>' + esc(label) + '</button>';
}

function emptyState(icon, text) {
    return '<div class="empty-state"><div class="empty-icon">' + icon + '</div><div>' + esc(text) + '</div></div>';
}

function esc(str) {
    str = (str === null || str === undefined) ? '' : String(str);
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
              .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

function fmtNum(n) {
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

function setContent(html) {
    hideTooltip();
    contentEl.innerHTML = html;
    bindImageFallbacks(contentEl);
}

function goBackToMainMenu() {
    screenData.menuView = getDefaultMenuView(screenData.menuState);
    showMenu(screenData.menuState);
    sendAction('goBack', {});
}

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

// ARC info satırlarını "etiket: değer" düzenine ayırır; ayıracın olmadığı durumlarda tek blok metin döndürür.
function splitArcLine(text) {
    var value = String(text || '').trim();
    if (!value) return { label: 'ARC', value: '-' };
    var separatorIndex = value.indexOf(':');
    if (separatorIndex === -1) {
        return { label: 'ARC', value: value };
    }
    return {
        label: value.slice(0, separatorIndex).trim(),
        value: value.slice(separatorIndex + 1).trim()
    };
}

function getArcTeamMemberStatus(member) {
    if (member && member.isSelf) {
        return ARC_TEAM_STATUS.self;
    }
    if (member && member.isAlive === false) {
        return ARC_TEAM_STATUS.down;
    }
    return ARC_TEAM_STATUS.online;
}

function setArcHud(data) {
    data = data || {};
    var currentState = screenData.arcHud || {};
    var nextState = Object.assign({}, currentState, data);

    screenData.arcHud = nextState;
    renderArcHud();
}

function clearArcHud() {
    screenData.arcHud = {
        enabled: false,
        showInfo: false,
        title: ARC_HUD_DEFAULTS.title,
        subtitle: ARC_HUD_DEFAULTS.subtitle,
        lines: [],
        prompt: '',
        teamMembers: []
    };
    screenData.arcBanner = {
        visible: false,
        label: ARC_BANNER_DEFAULT_LABEL,
        title: ARC_BANNER_DEFAULT_TITLE,
        duration: ARC_BANNER_DEFAULT_DURATION,
        transition: false
    };
    clearArcProgress(true);
    clearArcBarricadePlacement(true);
    arcNotifyTimers.forEach(function (timerId) {
        clearTimeout(timerId);
    });
    arcNotifyTimers = [];
    if (arcBannerTimer) {
        clearTimeout(arcBannerTimer);
        arcBannerTimer = null;
    }
    hudEls.arcNotifyStack.innerHTML = '';
    renderArcHud();
}

function renderArcHud() {
    var state = screenData.arcHud || {};
    var bannerState = screenData.arcBanner || {};
    var progressState = screenData.arcProgress || {};
    var barricadePlacementState = screenData.arcBarricadePlacement || {};
    var teamMembers = Array.isArray(state.teamMembers) ? state.teamMembers : [];
    var infoLines = Array.isArray(state.lines) ? state.lines : [];
    var hasToasts = hudEls.arcNotifyStack.children.length > 0;
    var hasBanner = bannerState.visible === true && String(bannerState.title || '').trim().length > 0;
    var hasProgress = progressState.visible === true;
    var hasBarricadePlacement = barricadePlacementState.visible === true;
    var hasPrompt = String(state.prompt || '').trim().length > 0;
    var hasInfo = state.enabled === true && state.showInfo === true && (String(state.title || '').trim() || String(state.subtitle || '').trim() || infoLines.length > 0 || hasPrompt);

    hudEls.arcOverlayRoot.classList.toggle('hidden', state.enabled !== true && !hasToasts && !hasBanner && !hasProgress && !hasBarricadePlacement);
    hudEls.arcOverlayRoot.setAttribute('aria-hidden', (state.enabled === true || hasToasts || hasBanner || hasProgress || hasBarricadePlacement) ? 'false' : 'true');

    hudEls.arcInfoPanel.classList.toggle('hidden', !hasInfo);
    hudEls.arcTeamPanel.classList.toggle('hidden', !(state.enabled === true && teamMembers.length > 0));
    hudEls.arcResultBanner.classList.toggle('hidden', !hasBanner);
    hudEls.arcProgressCard.classList.toggle('hidden', !hasProgress);
    hudEls.arcBarricadePlacementCard.classList.toggle('hidden', !hasBarricadePlacement);
    hudEls.arcResultBanner.classList.toggle('is-transition', bannerState.transition === true);
    hudEls.arcResultBanner.style.setProperty('--arc-banner-duration', String(Number(bannerState.duration || ARC_BANNER_DEFAULT_DURATION)) + 'ms');
    hudEls.arcResultBannerLabel.textContent = bannerState.label || ARC_BANNER_DEFAULT_LABEL;
    hudEls.arcResultBannerTitle.textContent = bannerState.title || ARC_BANNER_DEFAULT_TITLE;
    hudEls.arcProgressTitle.textContent = progressState.title || ARC_PROGRESS_DEFAULT_TITLE;
    hudEls.arcProgressLabel.textContent = progressState.label || ARC_PROGRESS_DEFAULT_LABEL;
    hudEls.arcProgressCancel.textContent = progressState.canCancel === false ? ARC_PROGRESS_CANCEL_DISABLED_TEXT : ARC_PROGRESS_CANCEL_ENABLED_TEXT;
    hudEls.arcBarricadePlacementTitle.textContent = barricadePlacementState.title || 'ARC Barricade Kit';
    hudEls.arcBarricadePlacementControls.innerHTML = (Array.isArray(barricadePlacementState.controls) ? barricadePlacementState.controls : []).map(function (control) {
        control = control || {};
        return '<div class="arc-barricade-placement-control">' +
            '<span class="arc-barricade-placement-key">' + esc(control.key || '-') + '</span>' +
            '<span class="arc-barricade-placement-action">' + esc(control.action || '') + '</span>' +
        '</div>';
    }).join('');
    updateArcProgressVisuals(Date.now());

    hudEls.arcInfoTitle.textContent = state.title || ARC_HUD_DEFAULTS.title;
    hudEls.arcInfoSubtitle.textContent = state.subtitle || ARC_HUD_DEFAULTS.subtitle;
    hudEls.arcInfoLines.innerHTML = infoLines.map(function (line) {
        var parsed = splitArcLine(line);
        return '<div class="arc-info-line">' +
            '<span class="arc-info-line-label">' + esc(parsed.label || 'ARC') + '</span>' +
            '<span class="arc-info-line-value">' + esc(parsed.value || '-') + '</span>' +
        '</div>';
    }).join('');

    hudEls.arcInfoPrompt.textContent = state.prompt || '';
    hudEls.arcInfoPrompt.classList.toggle('hidden', !hasPrompt);
    if (hudEls.arcTeamCount) {
        hudEls.arcTeamCount.textContent = teamMembers.length + ' ' + ARC_TEAM_COUNT_TEXT;
    }

    hudEls.arcTeamMembers.innerHTML = teamMembers.map(function (member) {
        member = member || {};
        var status = getArcTeamMemberStatus(member);
        var isSelf = status === ARC_TEAM_STATUS.self;
        var isDown = status === ARC_TEAM_STATUS.down;
        var classes = 'arc-team-member';
        if (isSelf) classes += ' is-self';
        if (isDown) classes += ' is-down';
        return '<div class="' + classes + '">' +
            '<span class="arc-team-member-bar"></span>' +
            '<div class="arc-team-member-body">' +
                '<div class="arc-team-member-top">' +
                    '<div class="arc-team-member-name">' + esc(member.name || 'Bilinmeyen Operatör') + '</div>' +
                    '<div class="arc-team-member-state">' + esc(status.badge) + '</div>' +
                '</div>' +
                '<div class="arc-team-member-meta">' + esc(status.text) + '</div>' +
            '</div>' +
        '</div>';
    }).join('');
    updateArcBarricadePlacementPosition(state.enabled === true && teamMembers.length > 0);
}

function cancelArcProgressFrame() {
    if (arcProgressFrame) {
        cancelAnimationFrame(arcProgressFrame);
        arcProgressFrame = null;
    }
}

function updateArcProgressVisuals(currentTime) {
    var progressState = screenData.arcProgress || {};
    var percent = 0;
    var duration = Number(progressState.duration || 0);
    var startedAt = Number(progressState.startedAt || 0);
    var now = Number(currentTime || Date.now());

    if (progressState.visible === true && duration > 0) {
        percent = clamp(((now - startedAt) / duration) * 100, 0, 100);
    }

    if (hudEls.arcProgressFill) {
        hudEls.arcProgressFill.style.width = percent + '%';
    }
    if (hudEls.arcProgressPercent) {
        hudEls.arcProgressPercent.textContent = Math.round(percent) + '%';
    }
}

function tickArcProgress() {
    cancelArcProgressFrame();
    var progressState = screenData.arcProgress || {};
    var duration = Number(progressState.duration || 0);
    var startedAt = Number(progressState.startedAt || 0);
    var now = Date.now();

    if (!progressState || progressState.visible !== true) {
        updateArcProgressVisuals(now);
        return;
    }

    updateArcProgressVisuals(now);

    if ((now - startedAt) < duration) {
        arcProgressFrame = requestAnimationFrame(tickArcProgress);
    } else if (progressState.completedNotified !== true) {
        progressState.completedNotified = true;
        sendAction('arcProgressComplete', {
            id: Number(progressState.id || 0)
        });
    }
}

function clearArcProgress(skipRender) {
    cancelArcProgressFrame();
    screenData.arcProgress = getDefaultArcProgressState();
    if (!skipRender) {
        renderArcHud();
    }
}

function clearArcBarricadePlacement(skipRender) {
    screenData.arcBarricadePlacement = getDefaultArcBarricadePlacementState();
    if (!skipRender) {
        renderArcHud();
    }
}

function updateArcBarricadePlacementPosition(hasTeamPanel) {
    if (!hudEls.arcBarricadePlacementCard) {
        return;
    }

    var bottomOffset = ARC_BARRICADE_DEFAULT_BOTTOM_OFFSET;
    var teamPanel = hudEls.arcTeamPanel;
    if (hasTeamPanel && teamPanel && !teamPanel.classList.contains('hidden')) {
        bottomOffset = teamPanel.offsetHeight + ARC_TEAM_PANEL_BOTTOM_OFFSET + ARC_BARRICADE_TEAM_PANEL_GAP;
    }

    hudEls.arcBarricadePlacementCard.style.bottom = bottomOffset + 'px';
}

function showArcBarricadePlacement(data) {
    data = data || {};
    screenData.arcBarricadePlacement = {
        visible: true,
        title: data.title || 'ARC Barricade Kit',
        controls: Array.isArray(data.controls) ? data.controls : []
    };
    renderArcHud();
}

function showArcProgress(data) {
    data = data || {};
    cancelArcProgressFrame();
    screenData.arcProgress = {
        visible: true,
        id: Number(data.id || 0),
        title: data.title || ARC_PROGRESS_DEFAULT_TITLE,
        label: data.label || ARC_PROGRESS_DEFAULT_LABEL,
        duration: clamp(Number(data.duration || 0), ARC_PROGRESS_MIN_DURATION, ARC_PROGRESS_MAX_DURATION),
        canCancel: data.canCancel !== false,
        startedAt: Date.now(),
        completedNotified: false
    };
    renderArcHud();
    tickArcProgress();
}

function pushArcNotify(data) {
    data = data || {};
    var root = hudEls.arcNotifyStack;
    var toast = document.createElement('div');
    var notifyType = String(data.type || 'info').toLowerCase();
    if (!ARC_NOTIFY_TYPES[notifyType]) {
        notifyType = 'info';
    }
    hudEls.arcOverlayRoot.classList.remove('hidden');
    hudEls.arcOverlayRoot.setAttribute('aria-hidden', 'false');
    toast.className = 'arc-notify is-' + notifyType;
    toast.innerHTML =
        '<div class="arc-notify-title">' + esc(data.title || 'ARC Bildirimi') + '</div>' +
        '<div class="arc-notify-message">' + esc(data.message || '') + '</div>';
    root.appendChild(toast);

    var duration = clamp(Number(data.duration || ARC_NOTIFY_DEFAULT_DURATION), ARC_NOTIFY_MIN_DURATION, ARC_NOTIFY_MAX_DURATION);
    var timerId = setTimeout(function () {
        arcNotifyTimers = arcNotifyTimers.filter(function (activeTimerId) {
            return activeTimerId !== timerId;
        });
        toast.classList.add('is-leaving');
        setTimeout(function () {
            if (toast.parentNode) {
                toast.parentNode.removeChild(toast);
            }
            renderArcHud();
        }, ARC_NOTIFY_EXIT_DURATION_MS);
    }, duration);
    arcNotifyTimers.push(timerId);
}

function clearArcBanner(skipRender) {
    if (arcBannerTimer) {
        clearTimeout(arcBannerTimer);
        arcBannerTimer = null;
    }
    screenData.arcBanner = {
        visible: false,
        label: ARC_BANNER_DEFAULT_LABEL,
        title: ARC_BANNER_DEFAULT_TITLE,
        duration: ARC_BANNER_DEFAULT_DURATION,
        transition: false
    };
    if (!skipRender) {
        renderArcHud();
    }
}

function showArcBanner(data) {
    data = data || {};
    clearArcBanner(true);
    screenData.arcBanner = {
        visible: true,
        label: data.label || ARC_BANNER_DEFAULT_LABEL,
        title: data.title || ARC_BANNER_DEFAULT_TITLE,
        duration: clamp(Number(data.duration || ARC_BANNER_DEFAULT_DURATION), ARC_BANNER_MIN_DURATION, ARC_BANNER_MAX_DURATION),
        transition: data.transition === true
    };
    renderArcHud();

    arcBannerTimer = setTimeout(function () {
        clearArcBanner();
    }, screenData.arcBanner.duration);
}

function bindImageFallbacks(root) {
    if (!root) return;
    root.querySelectorAll('img[data-fallback-src]').forEach(function (img) {
        if (img.dataset.fallbackBound === '1') return;
        img.dataset.fallbackBound = '1';
        img.addEventListener('error', function () {
            if (img.dataset.fallbackApplied === '1') return;
            img.dataset.fallbackApplied = '1';
            img.src = img.getAttribute('data-fallback-src') || '';
        });
    });
}

function setHudState(data) {
    data = data || {};
    var fallbackLobbyMembers = (screenData.menuState && screenData.menuState.lobbyMembers) || [];
    var nextLobbyMembers = Array.isArray(data.lobbyMembers) ? data.lobbyMembers : fallbackLobbyMembers;
    var shouldShowLobbyMembers = data.showLobbyMembers !== undefined
        ? data.showLobbyMembers
        : ((screenData.menuState && screenData.menuState.hasLobby) === true);
    refreshOperatorStatus(data.operatorCards);
    renderLobbyMembersPanel(nextLobbyMembers, shouldShowLobbyMembers);
    hudEls.missionBrief.classList.toggle('hidden', data.hideMissionBrief === true);

    hudEls.briefTitle.textContent = data.briefTitle || DEFAULT_HUD.briefTitle;
    hudEls.briefText.textContent = data.briefText || DEFAULT_HUD.briefText;
    if (data.briefExtractionPhase || data.briefExtractionObjective || data.briefExtractionCountdown) {
        hudEls.briefExtraction.classList.remove('hidden');
        hudEls.briefExtractionPhase.textContent = data.briefExtractionPhase || DEFAULT_HUD.briefExtractionPhase || 'Tahliye Hazır';
        hudEls.briefExtractionObjective.textContent = data.briefExtractionObjective || DEFAULT_HUD.briefExtractionObjective || '';
        hudEls.briefExtractionCountdown.textContent = data.briefExtractionCountdown || DEFAULT_HUD.briefExtractionCountdown || '';
    } else {
        hudEls.briefExtraction.classList.add('hidden');
        hudEls.briefExtractionPhase.textContent = '';
        hudEls.briefExtractionObjective.textContent = '';
        hudEls.briefExtractionCountdown.textContent = '';
    }
    hudEls.briefTag.textContent = data.briefTag || DEFAULT_HUD.briefTag;
    hudEls.briefTag.disabled = true;
    hudEls.briefTag.className = 'pubg-ready-btn is-static';
    hudEls.briefTag.removeAttribute('data-tip');
    hudEls.briefProgress.style.width = clamp(data.progress || DEFAULT_HUD.progress, 0, 100) + '%';
}

function setMeter(valueNode, barNode, value, suffix, overrideText) {
    var text = overrideText || (value + (suffix || ''));
    valueNode.textContent = text;
    valueNode.setAttribute('aria-label', text);
    barNode.style.width = value + '%';
}

function refreshOperatorStatus(cards) {
    cards = cards || buildOperatorCards();
    hudEls.statusTitle.textContent = 'OPERATÖR BİLGİSİ';
    setStatusCard(hudEls.healthLabel, hudEls.healthValue, hudEls.healthBar, cards[0], '#a8d5e2');
    setStatusCard(hudEls.radiationLabel, hudEls.radiationValue, hudEls.radiationBar, cards[1], '#ff4a4a');
    setStatusCard(hudEls.inventoryLabel, hudEls.inventoryValue, hudEls.inventoryBar, cards[2], '#7aff7a');
    setStatusCard(hudEls.signalLabel, hudEls.signalValue, hudEls.signalBar, cards[3], '#f2a900');
}

function setStatusCard(labelNode, valueNode, barNode, card, color) {
    card = card || {};
    labelNode.textContent = card.label || 'DURUM';
    labelNode.style.color = color;
    valueNode.textContent = card.value || '-';
    valueNode.setAttribute('aria-label', card.value || '-');
    barNode.style.width = clamp(card.valuePct || 18, 0, 100) + '%';
    barNode.style.background = color;
}

function buildOperatorCards() {
    var state = screenData.menuState || {};
    var playerName = state.playerName || 'Bilinmeyen Operatif';
    var currentStage = Number(state.currentStage || 1);
    var upgradeLabel = state.upgradeLabel || 'Standart Paket';
    var lobbyStatus = state.lobbyStatus || 'Solo';

    return [
        {
            label: 'KARAKTER',
            value: playerName,
            valuePct: clamp(playerName.length * 7, 24, 100)
        },
        {
            label: 'BÖLGE',
            value: 'Bölüm ' + currentStage,
            valuePct: clamp(currentStage * 18, 18, 100)
        },
        {
            label: 'GELİŞTİRME',
            value: upgradeLabel,
            valuePct: upgradeLabel === 'Standart Paket' ? 36 : 82
        },
        {
            label: 'TAKIM',
            value: lobbyStatus,
            valuePct: state.hasLobby ? (state.isLeader ? 88 : 74) : 28
        }
    ];
}

function getLobbyMemberStatusText(member) {
    if (member && member.isLeader) return 'Lider';
    return member && member.isReady ? 'Hazır' : 'Hazır Değil';
}

function renderLobbyMembersPanel(members, shouldShow) {
    if (!hudEls.lobbyMembersPanel || !hudEls.lobbyMembersList) return;

    if (shouldShow !== true || !Array.isArray(members) || members.length === 0) {
        hudEls.lobbyMembersPanel.classList.add('hidden');
        hudEls.lobbyMembersList.innerHTML = '';
        return;
    }

    hudEls.lobbyMembersPanel.classList.remove('hidden');
    hudEls.lobbyMembersList.innerHTML = members.slice(0, MAX_LOBBY_SIZE).map(function (member) {
        member = member || {};
        var statusText = getLobbyMemberStatusText(member);
        return '<div class="lobby-member-card">' +
            '<div class="lobby-member-row">' +
                '<div class="lobby-member-name">' + esc(member.name || ('Oyuncu #' + String(member.id || '?'))) + '</div>' +
                '<div class="lobby-member-badge' + (member.isLeader ? ' is-leader' : (member.isReady ? ' is-ready' : ' is-waiting')) + '">' + esc(statusText) + '</div>' +
            '</div>' +
            '<div class="lobby-member-meta">ID: ' + esc(String(member.id || '-')) + '</div>' +
        '</div>';
    }).join('');
}

function formatSecondsClock(totalSeconds) {
    totalSeconds = Math.floor(Math.max(0, Number(totalSeconds || 0)));
    var minutes = Math.floor(totalSeconds / 60);
    var seconds = totalSeconds % 60;
    return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
}

function buildArcExtractionPanel(state) {
    var extraction = state.arcExtraction || (state.arcSummary && state.arcSummary.extraction) || {};
    if (!extraction || extraction.enabled !== true) return '';
    var countdown = Number(extraction.countdown || extraction.availableIn || 0);
    var readyWindow = Number(extraction.readyWindow || 0);
    var manualDepartureEnabled = extraction.manualDepartureEnabled !== false;
    var autoDepartureOnTimeout = extraction.autoDepartureOnTimeout !== false;
    var departureMode = manualDepartureEnabled && autoDepartureOnTimeout
        ? 'Manuel veya süre bitince bölgedekiler'
        : manualDepartureEnabled
            ? 'Sadece manuel kalkış'
            : autoDepartureOnTimeout
                ? 'Süre bitince bölgedekiler'
                : 'Manuel/otomatik kalkış kapalı';
    return '<div class="arc-extraction-panel">' +
        '<div class="arc-extraction-row"><strong>' + esc(extraction.phaseLabel || 'Tahliye Hazır') + '</strong><span>' + esc(extraction.objective || 'Tahliye objective güncelleniyor.') + '</span></div>' +
        '<div class="arc-extraction-row"><span>Unlock / Sayaç</span><span>' + esc(countdown > 0 ? formatSecondsClock(countdown) : 'Hazır') + '</span></div>' +
        '<div class="arc-extraction-row"><span>Çağrı / Ready</span><span>' + esc(String(extraction.callDelay || 0)) + 's / ' + esc(String(readyWindow || 0)) + 's</span></div>' +
        '<div class="arc-extraction-row"><span>Kalkış Modu</span><span>' + esc(departureMode) + '</span></div>' +
    '</div>';
}

function screenMeter(label, value) {
    return '<div class="card-meter"><span class="card-meter-label">' + esc(label) + '</span><div class="card-meter-bar"><span style="width:' + clamp(value, 8, 100) + '%"></span></div></div>';
}

function describeCount(count, singular, plural) {
    return count + ' ' + (count === 1 ? singular : plural);
}

function setMainNavigationVisible(visible) {
    hudEls.menuSidebarShell.classList.toggle('hidden', visible !== true);
}

function renderMenuSidebar(html) {
    hudEls.menuSidebar.innerHTML = html || '';
}

function hideMainNavigation() {
    setMainNavigationVisible(false);
    renderMenuSidebar('');
}

function getNavItemBySection(sectionKey) {
    return MENU_NAV_ITEMS.find(function (item) {
        return item.key === sectionKey;
    }) || MENU_NAV_ITEMS[0];
}

function getMenuPanelDefinition(panelKey) {
    for (var i = 0; i < MENU_NAV_ITEMS.length; i++) {
        var panel = (MENU_NAV_ITEMS[i].panels || []).find(function (entry) {
            return entry.key === panelKey;
        });
        if (panel) return panel;
    }
    return MENU_NAV_ITEMS[0].panels[0];
}

function getSectionDefaultPanel(sectionKey) {
    var item = getNavItemBySection(sectionKey);
    return item && item.panels && item.panels[0] ? item.panels[0].key : null;
}

function getDefaultMenuView(state) {
    var defaultSection = MENU_NAV_ITEMS[0] || {};
    return {
        section: defaultSection.key || null,
        panel: getSectionDefaultPanel(defaultSection.key)
    };
}

function syncMenuView(state) {
    var fallback = getDefaultMenuView(state);
    var view = screenData.menuView || fallback;
    if (!view.section) {
        screenData.menuView = fallback;
        return screenData.menuView;
    }

    var activeSection = MENU_NAV_ITEMS.find(function (item) {
        return item.key === view.section;
    });
    if (!activeSection) {
        screenData.menuView = fallback;
        return screenData.menuView;
    }

    var panelKey = view.panel || null;
    if (panelKey) {
        var hasPanel = (activeSection.panels || []).some(function (panel) {
            return panel.key === panelKey;
        });
        if (!hasPanel) {
            panelKey = getSectionDefaultPanel(activeSection.key);
        }
    } else {
        panelKey = getSectionDefaultPanel(activeSection.key);
    }

    screenData.menuView = {
        section: activeSection.key,
        panel: panelKey
    };
    return screenData.menuView;
}

function ensureMenuSelections(state) {
    state = state || {};
    if (!screenData.menuSelections.arcZoneId) {
        screenData.menuSelections.arcZoneId = state.selectedArcZoneId || (state.arcDeploymentZones && state.arcDeploymentZones[0] && state.arcDeploymentZones[0].id) || null;
    }
    if (!screenData.menuSelections.survivalStageId) {
        screenData.menuSelections.survivalStageId = state.selectedSurvivalStageId || (state.survivalStages && state.survivalStages[0] && state.survivalStages[0].id) || null;
    }
}

function selectMenuSection(sectionKey) {
    var item = getNavItemBySection(sectionKey);
    screenData.menuView = {
        section: item.key,
        panel: getSectionDefaultPanel(item.key)
    };
    if (currentScreen === 'menu') {
        showMenu(screenData.menuState);
    }
}

function getDirectPanelAction(panelKey) {
    switch (panelKey) {
        case 'arcLoadout':
            return { action: 'openArcLoadoutStash', data: {} };
        case 'arcWorkshop':
            return { action: 'openCraft', data: { source: 'arc_main' } };
        case 'arcDepot':
            return { action: 'openArcMainStash', data: {} };
        case 'survivalMarket':
            return { action: 'openMarket', data: {} };
        case 'survivalWorkshop':
            return { action: 'openCraft', data: {} };
        default:
            return null;
    }
}

function selectMenuPanel(sectionKey, panelKey) {
    var directAction = getDirectPanelAction(panelKey);
    if (directAction) {
        screenData.menuView = {
            section: sectionKey,
            panel: null
        };
        sendAction(directAction.action, directAction.data);
        return;
    }

    screenData.menuView = {
        section: sectionKey,
        panel: panelKey
    };
    if (currentScreen === 'menu') {
        showMenu(screenData.menuState);
    }
}

function selectArcZone(zoneId) {
    screenData.menuSelections.arcZoneId = zoneId;
    if (currentScreen === 'menu') {
        showMenu(screenData.menuState);
    }
}

function selectSurvivalStage(stageId) {
    screenData.menuSelections.survivalStageId = stageId;
    if (currentScreen === 'menu') {
        showMenu(screenData.menuState);
    }
}

function renderPopupStat(label, value, desc) {
    return '<div class="menu-popup-stat">' +
        '<div class="menu-popup-stat-label">' + esc(label) + '</div>' +
        '<div class="menu-popup-stat-value">' + esc(value) + '</div>' +
        (desc ? '<div class="menu-popup-stat-desc">' + esc(desc) + '</div>' : '') +
    '</div>';
}

function renderChoiceCard(options) {
    options = options || {};
    var cls = 'menu-choice-card' + (options.selected ? ' is-selected' : '') + (options.disabled ? ' is-disabled' : '');
    return '<button class="' + cls + '" type="button"' +
        (options.disabled ? ' disabled' : '') +
        (!options.disabled && options.onclick ? ' onclick="' + options.onclick + '"' : '') +
        (options.tip ? ' data-tip="' + esc(options.tip) + '"' : '') + '>' +
        '<div class="menu-choice-top">' +
            '<span class="menu-choice-chip">' + esc(options.kicker || 'SEÇİM') + '</span>' +
            '<span class="menu-choice-chip">' + esc(options.chip || 'HAZIR') + '</span>' +
        '</div>' +
        '<div class="menu-choice-title">' + esc(options.title || 'Bilinmiyor') + '</div>' +
        (options.desc ? '<div class="menu-choice-desc">' + esc(options.desc) + '</div>' : '') +
        (options.meta && options.meta.length ? '<div class="menu-choice-meta">' + options.meta.map(function (item) {
            return '<span>' + esc(item) + '</span>';
        }).join('') + '</div>' : '') +
    '</button>';
}

function buildSidebarHtml(state, view) {
    var html = '<div class="menu-sidebar-panel">' +
        '<div class="menu-sidebar-kicker">Kontrol Menüsü</div>' +
        '<div class="menu-sidebar-title">SOL NAVİGASYON</div>';

    MENU_NAV_ITEMS.forEach(function (item) {
        var isActiveSection = view.section === item.key;
        html += '<div class="menu-sidebar-group">' +
            '<button class="menu-sidebar-main' + (isActiveSection ? ' is-active' : '') + '" type="button" onclick="selectMenuSection(\'' + item.key + '\')">' +
                '<span class="menu-sidebar-main-label">' + esc(item.label) + '</span>' +
                '<span class="menu-sidebar-main-meta">' + esc(item.meta) + '</span>' +
            '</button>';

        if (isActiveSection) {
            html += '<div class="menu-sidebar-sublist">';
            item.panels.forEach(function (panel) {
                html += '<button class="menu-sidebar-subitem' + (view.panel === panel.key ? ' is-active' : '') + '" type="button" onclick="selectMenuPanel(\'' + item.key + '\',\'' + panel.key + '\')">' +
                    '<span class="menu-sidebar-subitem-label">' + esc(panel.label) + '</span>' +
                    '<span class="menu-sidebar-subitem-desc">' + esc(panel.desc) + '</span>' +
                '</button>';
            });
            html += '</div>';
        }

        html += '</div>';
    });

    return html + '<div class="menu-sidebar-footer">Karakter ön izlemesi açık kalır. Sol menüden seç, sağdaki büyük pencereden yönet.</div></div>';
}

function renderMenuPopupFrame(config) {
    config = config || {};
    return '<div class="menu-shell"><section class="menu-popup">' +
        '<div class="menu-popup-header">' +
            '<div>' +
                '<div class="menu-popup-kicker">' + esc(config.kicker || 'OPERASYON') + '</div>' +
                '<div class="menu-popup-title">' + esc(config.title || 'Kontrol Penceresi') + '</div>' +
                (config.desc ? '<div class="menu-popup-desc">' + esc(config.desc) + '</div>' : '') +
            '</div>' +
            (config.note ? '<div class="menu-popup-note">' + config.note + '</div>' : '') +
        '</div>' +
        '<div class="menu-popup-body">' + (config.body || '') + '</div>' +
        (config.footer || '') +
    '</section></div>';
}

function renderMenuPopupFooter(primaryLabel, primaryAction, footerCopy, disabled) {
    var statusClass = disabled ? ' is-unavailable is-static' : ' is-available';
    return '<div class="menu-popup-footer">' +
        '<div class="menu-popup-actions">' +
            '<button class="pubg-ready-btn menu-popup-start' + statusClass + '" type="button" ' +
                (disabled ? 'disabled' : '') + ' onclick="' + primaryAction + '">' + esc(primaryLabel) + '</button>' +
        '</div>' +
        '<div class="menu-popup-footer-copy">' + esc(footerCopy || '') + '</div>' +
    '</div>';
}

function renderMenuLanding(state, view) {
    var sectionLabel = view.section ? getNavItemBySection(view.section).label : 'Operasyon';
    return renderMenuPopupFrame({
        kicker: 'BEKLEME',
        title: 'Soldan Bir Menü Seç',
        desc: 'Menü ilk açıldığında içerik otomatik yüklenmez. Soldaki başlıklardan bölüm seçip ilgili ekranı kendin açarsın.',
        note: '<strong>' + esc(sectionLabel) + '</strong><br>İçerik seçimi bekleniyor.',
        body: '<div class="menu-popup-grid">' +
            renderPopupStat('Karakter', state.playerName || 'Bilinmeyen Operatif', 'Ön izleme açık kalır.') +
            renderPopupStat('Takım', state.lobbyStatus || 'Tek Başına', 'Hazırlık ve lobby bilgileri soldan yönetilir.') +
            renderPopupStat('Mod', state.currentModeLabel || 'Klasik Hayatta Kalma', 'ARC ve survival akışları soldaki menüden açılır.') +
        '</div>'
    });
}

function renderArcRaidPanel(state) {
    var summary = state.arcSummary || {};
    var loadoutUi = getArcLoadoutPresentation(state);
    var canDeploy = summary.canDeploy !== false;

    var body = '<div class="menu-popup-grid">' +
            renderPopupStat('Lider Yetkisi', state.isLeader ? 'Aktif' : 'Lider Gerekli', state.isLeader ? 'Operasyonu sen başlatabilirsin.' : 'Başlatma sadece lobi liderinde.') +
            renderPopupStat('Takım Hazır mı', canDeploy ? 'Hazır' : 'Eksik Var', canDeploy ? 'Kritik engel görünmüyor.' : 'Önce eksikleri tamamla.') +
            renderPopupStat('Baskın Çantası', loadoutUi.title, loadoutUi.detail) +
            renderPopupStat('Bağlantı Koparsa', state.disconnectPolicyLabel || 'Güvenli Dönüş', state.disconnectPolicyDescription || 'Kopma durumunda ARC politikası uygulanır.') +
        '</div>' +
        renderArcPreflightSummary(state) +
        buildArcExtractionPanel(state) +
        '<div class="section-header"><div class="section-title">&#127920; Rastgele Konuşlandırma</div></div>' +
        '<div class="menu-choice-grid">' +
            renderChoiceCard({
                selected: true,
                disabled: true,
                kicker: 'ARC',
                chip: 'RASTGELE',
                title: 'Otomatik Baskın Bölgesi',
                desc: 'ARC baskını başladığında sistem seni uygun deployment bölgesine otomatik ve rastgele yerleştirecek.',
                meta: [
                    'Konuşlandırma: Rastgele',
                    'Giriş Noktası: Otomatik',
                    'Tahliye: Operasyona göre'
                ],
                tip: 'ARC baskınında manuel bölge seçimi kapalıdır.'
            }) +
        '</div>';

    return renderMenuPopupFrame({
        kicker: 'ARC MODU',
        title: 'ARC Baskınını Başlat',
        desc: 'Baskın merkezi artık tek pencerede. Hazırlık özetini kontrol et; operasyon başlayınca sistem seni rastgele uygun bir ARC bölgesine bırakır.',
        note: '<strong>Rastgele Bölge</strong><br>Konuşlandırma sunucu tarafından otomatik belirlenir.',
        body: body,
        footer: renderMenuPopupFooter('ARC BASKININI BAŞLAT', 'startArcModeFromMenu()', canDeploy ? 'Baskın başladığında rastgele deployment bölgesi seçilecek.' : 'Kritik ARC hazırlıkları tamamlanmadan başlatılamaz.', !canDeploy)
    });
}

function renderArcActionPanel(title, desc, stats, actionLabel, actionJs, footerCopy) {
    return renderMenuPopupFrame({
        kicker: 'ARC MODU',
        title: title,
        desc: desc,
        body: '<div class="menu-popup-grid">' + stats.join('') + '</div>',
        footer: '<div class="menu-popup-footer"><div class="menu-popup-actions">' +
            '<button class="btn btn-primary" type="button" onclick="' + actionJs + '">' + esc(actionLabel) + '</button>' +
        '</div><div class="menu-popup-footer-copy">' + esc(footerCopy || '') + '</div></div>'
    });
}

function renderSurvivalRaidPanel(state) {
    var stages = state.survivalStages || [];
    var selectedStageId = screenData.menuSelections.survivalStageId;
    var selectedStage = stages.find(function (stage) { return stage.id === selectedStageId; }) || stages[0];
    var stageCards = stages.map(function (stage) {
        return renderChoiceCard({
            selected: stage.id === (selectedStage && selectedStage.id),
            onclick: stage.locked ? '' : 'selectSurvivalStage(' + Number(stage.id) + ')',
            kicker: stage.locked ? 'KİLİTLİ' : 'HARİTA',
            chip: stage.locked ? 'SEVİYE' : ('x' + stage.multiplier),
            title: stage.label,
            desc: stage.locked ? 'Bu harita mevcut seviyende kapalı.' : 'Seçimi yaptıktan sonra sol alttan başlat.',
            meta: [
                'Zorluk x' + stage.multiplier,
                stage.locked ? 'Açılmadı' : 'Hazır',
                stage.enemyLabel || 'Dalga modu'
            ],
            tip: stage.locked ? (stage.label + ' kilitli.') : (stage.label + ' seçildiğinde sol alttan başlatılır.')
        });
    }).join('');

    return renderMenuPopupFrame({
        kicker: 'HAYATTA KALMA',
        title: 'Haritayı Seç',
        desc: 'Hayatta kalma modunda karakterin ön izlemede kalır, haritayı seçersin ve operasyonu sol alttaki butondan başlatırsın.',
        note: '<strong>Seviye ' + esc(String(state.userLevel || 1)) + '</strong><br>' + esc(state.upgradeLabel || 'Standart Paket'),
        body: '<div class="menu-popup-grid">' +
                renderPopupStat('Aktif Operatif', state.playerName || 'Bilinmeyen Operatif', 'Karakter ön izlemesi menü boyunca açık kalır.') +
                renderPopupStat('Takım Durumu', state.lobbyStatus || 'Tek Başına', state.hasLobby ? 'Takımınla birlikte girebilirsin.' : 'İstersen solo başlayabilirsin.') +
                renderPopupStat('Hazırlık', state.isReady ? 'Hazır' : 'Beklemede', state.isMember ? 'Hazır butonu lobi ayarlarında bulunur.' : 'Solo modda doğrudan başlayabilirsin.') +
            '</div>' +
            '<div class="section-header"><div class="section-title">&#128205; Operasyon Haritaları</div></div>' +
            '<div class="menu-choice-grid">' + stageCards + '</div>',
        footer: renderMenuPopupFooter('HAYATTA KALMAYI BAŞLAT', 'startSurvivalModeFromMenu()', selectedStage ? ('Seçilen harita: ' + selectedStage.label) : 'Önce bir harita seç.', !selectedStage || selectedStage.locked)
    });
}

function renderLobbySettingsPanel(state) {
    var lobbyActions = [];
    if (!state.hasLobby) {
        lobbyActions.push('<button class="btn btn-primary" type="button" onclick="createLobbyFromMenu(true)">PUBLIC LOBİ KUR</button>');
        lobbyActions.push('<button class="btn" type="button" onclick="createLobbyFromMenu(false)">PRIVATE LOBİ KUR</button>');
    } else {
        lobbyActions.push('<button class="btn btn-primary" type="button" onclick="handleReadyButton()">' + esc(state.isReady ? 'HAZIRLIĞI KALDIR' : 'HAZIR OL') + '</button>');
        lobbyActions.push('<button class="btn" type="button" onclick="sendAction(\'openMembers\',{})">TAKIMI GÖR</button>');
        if (state.isLeader) {
            lobbyActions.push('<button class="btn" type="button" onclick="sendAction(\'openInvite\',{})">OYUNCU DAVET ET</button>');
            lobbyActions.push('<button class="btn btn-danger" type="button" onclick="sendAction(\'disbandLobby\',{})">LOBİYİ DAĞIT</button>');
        } else if (state.isMember) {
            lobbyActions.push('<button class="btn btn-danger" type="button" onclick="sendAction(\'leaveLobby\',{})">LOBİDEN AYRIL</button>');
        }
    }
    lobbyActions.push('<button class="btn" type="button" onclick="sendAction(\'openActiveLobbies\',{})">AKTİF LOBİLER</button>');

    return renderMenuPopupFrame({
        kicker: 'LOBİ',
        title: 'Lobi Ayarları',
        desc: 'Sol taraftaki lobi menüsünden takım akışını yönet, hazır durumunu kontrol et ve ayrıntı ekranlarını gerektiğinde aç.',
        note: '<strong>' + esc(state.lobbyStatus || 'Tek Başına') + '</strong><br>' + esc(state.isLeader ? 'Lider sensin.' : state.isMember ? 'Bir takıma bağlısın.' : 'Henüz takımın yok.'),
        body: '<div class="menu-popup-grid">' +
                renderPopupStat('Lider Yetkisi', state.isLeader ? 'Açık' : 'Kapalı', state.isLeader ? 'Operasyon ve davet yetkisi sende.' : 'Başlatma liderde.') +
                renderPopupStat('Takım Hazır mı', state.isReady ? 'Evet' : 'Hayır', 'Hazır durumunu bu pencereden değiştir.') +
                renderPopupStat('Oyuncu Sayısı', state.hasLobby ? (state.lobbyMemberCount || 'Takım Aktif') : 'Solo', state.hasLobby ? 'Takım bilgisi telemetri ekranında açılır.' : 'Dilersen lobi kurabilirsin.') +
            '</div>' +
            '<div class="menu-popup-actions">' + lobbyActions.join('') + '</div>',
        footer: '<div class="menu-popup-footer"><div class="menu-popup-actions"></div><div class="menu-popup-footer-copy">Lobi detayları gerektiğinde ayrı pencere olarak açılır; ana ayarlar burada tutulur.</div></div>'
    });
}

function hasActiveMenuSelection(view) {
    return !!(view && (view.section || view.panel));
}

function renderMenuPanel(state, view) {
    if (!hasActiveMenuSelection(view)) {
        return renderMenuPanel(state, getDefaultMenuView(state));
    }

    switch (view.panel) {
        case 'arcRaid':
            return renderArcRaidPanel(state);
        case 'arcLoadout':
        case 'arcWorkshop':
        case 'arcDepot':
        case 'survivalMarket':
        case 'survivalWorkshop':
            return renderMenuPanel(state, {
                section: view.section,
                panel: getSectionDefaultPanel(view.section)
            });
        case 'survivalRaid':
            return renderSurvivalRaidPanel(state);
        case 'lobbySettings':
            return renderLobbySettingsPanel(state);
        default:
            return renderMenuPanel(state, {
                section: view.section,
                panel: getSectionDefaultPanel(view.section)
            });
    }
}

function startArcModeFromMenu() {
    sendAction('startArcPvP', {});
}

function startSurvivalModeFromMenu() {
    if (!screenData.menuSelections.survivalStageId) return;
    sendAction('selectStage', {
        stageId: screenData.menuSelections.survivalStageId,
        modeId: 'classic'
    });
}

function createLobbyFromMenu(isPublic) {
    screenData.menuView = { section: 'lobby', panel: 'lobbySettings' };
    sendAction('createLobby', { isPublic: isPublic === true });
}

function showTooltip(text) {
    if (!text) {
        hideTooltip();
        return;
    }
    tooltipEl.textContent = text;
    tooltipEl.classList.remove('hidden');
}

function hideTooltip() {
    tooltipEl.classList.add('hidden');
}

function playUiTone(kind) {
    var AudioCtor = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtor) return;
    if (!audioCtx) {
        try {
            audioCtx = new AudioCtor();
        } catch (err) {
            console.debug('GS Survival UI audio init blocked:', err);
            return;
        }
    }
    if (audioCtx.state === 'suspended') {
        audioCtx.resume().then(function () {
            if (audioCtx.state === 'running') emitUiTone(kind);
        }).catch(function (err) {
            console.debug('GS Survival UI audio resume blocked:', err);
        });
        return;
    }
    if (audioCtx.state !== 'running') return;
    emitUiTone(kind);
}

function emitUiTone(kind) {
    var oscillator = audioCtx.createOscillator();
    var gainNode = audioCtx.createGain();
    oscillator.type = kind === 'alert' ? 'sawtooth' : 'triangle';
    oscillator.frequency.setValueAtTime(kind === 'alert' ? 180 : 420, audioCtx.currentTime);
    oscillator.frequency.exponentialRampToValueAtTime(kind === 'alert' ? 110 : 620, audioCtx.currentTime + 0.08);
    gainNode.gain.setValueAtTime(0.001, audioCtx.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.04, audioCtx.currentTime + 0.01);
    gainNode.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.11);
    oscillator.connect(gainNode);
    gainNode.connect(audioCtx.destination);
    oscillator.start();
    oscillator.stop(audioCtx.currentTime + 0.12);
}

function playMechanicalTone(profile) {
    var AudioCtor = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtor) return;
    if (!audioCtx) {
        try {
            audioCtx = new AudioCtor();
        } catch (err) {
            console.debug('GS Survival mechanical audio init blocked:', err);
            return;
        }
    }
    if (audioCtx.state === 'suspended') {
        audioCtx.resume().then(function () {
            if (audioCtx.state === 'running') emitMechanicalTone(profile);
        }).catch(function (err) {
            console.debug('GS Survival mechanical audio resume blocked:', err);
        });
        return;
    }
    if (audioCtx.state !== 'running') return;
    emitMechanicalTone(profile);
}

function emitMechanicalTone(profile) {
    var start = audioCtx.currentTime;
    var oscA = audioCtx.createOscillator();
    var oscB = audioCtx.createOscillator();
    var gain = audioCtx.createGain();
    var filter = audioCtx.createBiquadFilter();
    var isWorkshop = profile === 'workshop';

    oscA.type = isWorkshop ? 'square' : 'triangle';
    oscB.type = 'triangle';
    oscA.frequency.setValueAtTime(isWorkshop ? 180 : 640, start);
    oscB.frequency.setValueAtTime(isWorkshop ? 95 : 420, start);
    oscA.frequency.exponentialRampToValueAtTime(isWorkshop ? 110 : 380, start + (isWorkshop ? 0.07 : 0.05));
    oscB.frequency.exponentialRampToValueAtTime(isWorkshop ? 70 : 260, start + (isWorkshop ? 0.08 : 0.06));

    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(isWorkshop ? 1450 : 2200, start);
    gain.gain.setValueAtTime(0.001, start);
    gain.gain.exponentialRampToValueAtTime(isWorkshop ? 0.07 : 0.05, start + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.001, start + (isWorkshop ? 0.13 : 0.09));

    oscA.connect(filter);
    oscB.connect(filter);
    filter.connect(gain);
    gain.connect(audioCtx.destination);

    oscA.start(start);
    oscB.start(start + 0.003);
    oscA.stop(start + (isWorkshop ? 0.14 : 0.11));
    oscB.stop(start + (isWorkshop ? 0.12 : 0.08));
}

function updateMenuState(data) {
    data = data || {};
    var nextState = Object.assign({}, screenData.menuState, data);
    screenData.menuState = nextState;
    if (currentScreen === 'menu') {
        showMenu(screenData.menuState);
        return;
    }
    refreshOperatorStatus();
}

function setReadyButton(state) {
    state = state || {};
    var button = hudEls.briefTag;
    button.className = 'pubg-ready-btn';
    button.disabled = true;

    if (state.isMember) {
        if (state.isReady) {
            button.textContent = 'HAZIRLIĞI KALDIR';
            button.disabled = false;
            button.classList.add('is-pending');
            button.setAttribute('data-tip', 'Hazır durumun aktif. İstersen tekrar basıp hazır durumunu kaldırabilirsin.');
        } else {
            button.textContent = 'HAZIR OL';
            button.disabled = false;
            button.classList.add('is-member');
            button.setAttribute('data-tip', 'Lider operasyona başlamadan önce hazır durumunu onayla.');
        }
        return;
    }

    button.removeAttribute('data-tip');
    if (state.isLeader) {
        button.textContent = state.currentModeId === 'arc_pvp' ? 'BASKIN' : 'OPERASYON';
        button.classList.add('is-leader', 'is-static');
        return;
    }

    button.textContent = 'BEKLE';
    button.classList.add('is-static');
}

function syncLobbyMembers(data) {
    data = data || {};
    if (data.members) screenData.members = data.members;
    if (data.leaderId !== undefined) screenData.memberLeaderId = data.leaderId;
    if (data.members) screenData.menuState.lobbyMembers = data.members;
    if (currentScreen === 'members') {
        showMembers({
            members: screenData.members,
            leaderId: screenData.memberLeaderId
        });
    }
    if (currentScreen === 'menu') {
        renderLobbyMembersPanel(screenData.menuState.lobbyMembers || [], screenData.menuState.hasLobby === true);
    }
}

function handleReadyButton() {
    var state = screenData.menuState || {};
    if (currentScreen !== 'menu' || !state.isMember) return;
    playMechanicalTone('ready');
    state.isReady = !state.isReady;
    setReadyButton(state);
    showMenu(state);
    sendAction('toggleReady', {});
}

function stageCardArt(stage, idx) {
    var palettes = [
        ['#20140c', '#53402b', '#98713a'],
        ['#111b1b', '#224142', '#4f8b82'],
        ['#1a1612', '#4e2f23', '#956650'],
        ['#161820', '#33415e', '#7e91bf']
    ];
    var colors = palettes[idx % palettes.length];
    var label = esc(stage.label || ('Bölge ' + (idx + 1)));
    var svg = ''
        + '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 460" preserveAspectRatio="none">'
        + '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
        + '<stop offset="0%" stop-color="' + colors[1] + '"/><stop offset="100%" stop-color="' + colors[0] + '"/>'
        + '</linearGradient></defs>'
        + '<rect width="800" height="460" fill="' + colors[0] + '"/>'
        + '<rect width="800" height="460" fill="url(%23g)"/>'
        + '<g fill="none" stroke="' + colors[2] + '" stroke-width="16" opacity="0.32">'
        + '<path d="M40 360 L170 250 L325 295 L520 135 L760 185"/>'
        + '<path d="M92 122 L238 156 L402 88 L610 120 L738 80"/>'
        + '<path d="M160 418 L248 310 L438 352 L642 238"/>'
        + '</g>'
        + '<g fill="' + colors[2] + '" opacity="0.22">'
        + '<circle cx="184" cy="128" r="46"/><circle cx="510" cy="182" r="70"/><circle cx="654" cy="300" r="54"/>'
        + '</g>'
        + '<rect width="800" height="460" fill="#060606" fill-opacity="0.46"/>'
        + '<text x="46" y="410" font-size="56" font-family="Teko, Arial, sans-serif" fill="rgba(255,255,255,0.16)">' + label + '</text>'
        + '</svg>';
    return 'background-image:url("data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg) + '")';
}

function arcItemPlaceholder(label) {
    var safeLabel = String(label || '').trim();
    var text = esc((safeLabel ? safeLabel.charAt(0) : '?').toUpperCase());
    var svg = ''
        + '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96">'
        + '<defs><linearGradient id="arcItemBg" x1="0" y1="0" x2="1" y2="1">'
        + '<stop offset="0%" stop-color="#2a2a2a"/><stop offset="100%" stop-color="#111"/>'
        + '</linearGradient></defs>'
        + '<rect width="96" height="96" rx="18" fill="url(%23arcItemBg)"/>'
        + '<rect x="7" y="7" width="82" height="82" rx="14" fill="none" stroke="rgba(242,169,0,0.35)" stroke-width="2"/>'
        + '<text x="48" y="58" text-anchor="middle" font-size="38" font-family="Teko, Arial, sans-serif" fill="#f2a900">' + text + '</text>'
        + '</svg>';
    return 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg);
}

function arcItemImageUrl(item) {
    item = item || {};
    var image = item.image || (item.metadata && (item.metadata.imageurl || item.metadata.image)) || item.name || '';
    image = String(image || '').trim();

    if (!image) return arcItemPlaceholder(item.label || item.name);
    if (/^(https?:|data:|nui:|file:|\/|\.\/|\.\.\/)/i.test(image) || image.indexOf('cfx-nui-') !== -1) {
        return image;
    }

    image = image.replace(/^images\//i, '');
    if (!/\.[a-z0-9]+$/i.test(image)) image += '.png';

    return 'https://cfx-nui-ox_inventory/web/images/' + image.split('/').map(encodeURIComponent).join('/');
}

function arcMovePayload(sectionSide, slot, focusSide) {
    return '{fromSide:\'' + esc(sectionSide === 'loadout' ? 'loadout' : 'main') +
        '\',slot:' + Number(slot || 0) +
        ',focusSide:\'' + esc(focusSide === 'loadout' ? 'loadout' : 'main') + '\'}';
}

function getArcLockerSectionStats(section) {
    section = section || {};
    var items = Array.isArray(section.items) ? section.items : [];
    var totalSlots = Number(section.slots || 0);
    var totalItems = 0;

    items.forEach(function (item) {
        totalItems += Number((item && item.count) || 0);
    });

    return {
        items: items,
        totalSlots: totalSlots,
        usedSlots: items.length,
        freeSlots: Math.max(totalSlots - items.length, 0),
        totalItems: totalItems
    };
}

function getArcLockerCategory(item) {
    item = item || {};
    var haystack = (String(item.name || '') + ' ' + String(item.label || '') + ' ' + String(item.description || '')).toLowerCase();
    var keys = Object.keys(ARC_LOCKER_CATEGORY_RULES);

    if (item.isWeapon) return 'weapon';

    for (var i = 0; i < keys.length; i++) {
        var categoryKey = keys[i];
        var patterns = ARC_LOCKER_CATEGORY_RULES[categoryKey] || [];
        for (var j = 0; j < patterns.length; j++) {
            if (patterns[j].test(haystack)) {
                return categoryKey;
            }
        }
    }

    return 'misc';
}

function getArcLockerCategoryMeta(categoryKey) {
    for (var i = 0; i < ARC_LOCKER_CATEGORIES.length; i++) {
        if (ARC_LOCKER_CATEGORIES[i].key === categoryKey) return ARC_LOCKER_CATEGORIES[i];
    }
    return ARC_LOCKER_CATEGORIES[0];
}

function getArcLockerActiveCategory() {
    var lockers = screenData.arcLockers || {};
    return lockers.activeCategory || 'all';
}

function setArcLockerCategory(categoryKey) {
    var lockers = screenData.arcLockers || {};
    lockers.activeCategory = getArcLockerCategoryMeta(categoryKey).key;
    screenData.arcLockers = lockers;
    if (currentScreen === 'arcLockers') {
        showArcLockers(lockers);
    }
}

function getArcLockerFilteredItems(section) {
    section = section || {};
    var items = Array.isArray(section.items) ? section.items : [];
    var activeCategory = getArcLockerActiveCategory();

    if (activeCategory === 'all') return items;
    return items.filter(function (item) {
        return getArcLockerCategory(item) === activeCategory;
    });
}

function buildArcLockerCategoryCounts(items) {
    var counts = { all: 0 };
    ARC_LOCKER_CATEGORIES.forEach(function (category) {
        counts[category.key] = counts[category.key] || 0;
    });

    (items || []).forEach(function (item) {
        var categoryKey = getArcLockerCategory(item);
        counts.all += 1;
        counts[categoryKey] = (counts[categoryKey] || 0) + 1;
    });

    return counts;
}

function formatArcItemCount(count) {
    var value = Number(count || 0) || 0;
    function compactNumber(source, divisor, suffix) {
        return (Math.round((source / divisor) * 10) / 10) + suffix;
    }

    if (value < 1000) return String(value);
    if (value < 1000000) return compactNumber(value, 1000, 'k');
    return compactNumber(value, 1000000, 'm');
}

function renderArcLockerCategoryRail(section) {
    var items = Array.isArray(section && section.items) ? section.items : [];
    var counts = buildArcLockerCategoryCounts(items);
    var activeCategory = getArcLockerActiveCategory();
    var html = '<div class="arc-locker-rail" aria-label="Item kategorileri">';

    ARC_LOCKER_CATEGORIES.forEach(function (category) {
        var count = Number(counts[category.key] || 0);
        html += '<button class="arc-locker-rail-icon' + (activeCategory === category.key ? ' is-active' : '') + '" type="button" ' +
            'onclick="setArcLockerCategory(\'' + esc(category.key) + '\')" ' +
            'data-tip="' + esc(category.label + ' kategorisini filtrele (' + count + ' adet).') + '">' +
                '<span class="arc-locker-rail-icon-glyph">' + category.icon + '</span>' +
                '<span class="arc-locker-rail-icon-count">' + esc(String(count)) + '</span>' +
                '<span class="arc-locker-rail-icon-label">' + esc(category.label) + '</span>' +
        '</button>';
    });

    return html + '</div>';
}

function buildArcLockerMovePayload(fromSide, slot, focusSide, toSide, targetSlot) {
    return {
        fromSide: fromSide === 'loadout' ? 'loadout' : 'main',
        slot: Number(slot || 0),
        focusSide: focusSide === 'loadout' ? 'loadout' : 'main',
        toSide: toSide == null ? null : (toSide === 'loadout' ? 'loadout' : 'main'),
        targetSlot: targetSlot == null ? null : Number(targetSlot)
    };
}

function getArcLockerSectionBySide(lockers, side) {
    lockers = lockers || {};
    side = side === 'loadout' ? 'loadout' : 'main';
    return pickArcLockerSection(lockers.main, lockers.loadout, side);
}

function findArcLockerItem(lockers, side, slot) {
    var section = getArcLockerSectionBySide(lockers, side);
    var items = Array.isArray(section && section.items) ? section.items : [];
    slot = Number(slot || 0);

    for (var i = 0; i < items.length; i++) {
        if (Number(items[i] && items[i].slot) === slot) {
            return items[i];
        }
    }

    return null;
}

function closeArcLockerSplitDialog(skipRender) {
    if (!screenData.arcLockers) return;
    delete screenData.arcLockers.splitDialog;
    if (!skipRender && currentScreen === 'arcLockers') {
        showArcLockers(screenData.arcLockers);
    }
}

function openArcLockerSplitDialog(side, slot) {
    if (currentScreen !== 'arcLockers' || !screenData.arcLockers) return;

    var normalizedSide = side === 'loadout' ? 'loadout' : 'main';
    var item = findArcLockerItem(screenData.arcLockers, normalizedSide, slot);
    var itemCount = Number((item && item.count) || 0);
    if (!item || itemCount <= 1 || item.isWeapon) {
        pushArcNotify({
            type: 'info',
            title: 'Yığın Ayrılamıyor',
            message: 'Sağ tıkla ayırma yalnızca stacklenebilen ve adedi 1\'den büyük eşyalar için kullanılabilir.',
            duration: 3600
        });
        return;
    }

    var maxAmount = Math.max(itemCount - 1, 1);
    screenData.arcLockers.splitDialog = {
        fromSide: normalizedSide,
        targetSide: normalizedSide === 'loadout' ? 'main' : 'loadout',
        slot: Number(slot || 0),
        itemName: item.label || item.name || 'Eşya',
        totalCount: itemCount,
        maxAmount: maxAmount,
        amount: clamp(Math.round(itemCount * ARC_LOCKER_DEFAULT_SPLIT_RATIO), 1, maxAmount)
    };
    showArcLockers(screenData.arcLockers);
}

function normalizeArcLockerSplitAmount(rawValue, fallbackValue, maxAmount) {
    return clamp(
        Math.floor(Number((rawValue == null || rawValue === '') ? fallbackValue : rawValue)) || 1,
        1,
        Number(maxAmount || 1)
    );
}

function syncArcLockerSplitInputs(source) {
    var dialogState = screenData.arcLockers && screenData.arcLockers.splitDialog;
    if (!dialogState) return;

    var nextValue = normalizeArcLockerSplitAmount(source && source.value, dialogState.amount || 1, dialogState.maxAmount);
    dialogState.amount = nextValue;

    var rangeInput = document.getElementById('arc-split-amount-range');
    var numberInput = document.getElementById('arc-split-amount-input');
    var sourceCount = document.getElementById('arc-split-source-count');
    var targetCount = document.getElementById('arc-split-target-count');

    if (rangeInput && rangeInput !== source) rangeInput.value = String(nextValue);
    if (numberInput && numberInput !== source) numberInput.value = String(nextValue);
    if (sourceCount) sourceCount.textContent = 'Kaynakta kalacak: x' + String(Math.max(Number(dialogState.totalCount || 0) - nextValue, 0));
    if (targetCount) targetCount.textContent = 'Taşınacak: x' + String(nextValue);
}

function confirmArcLockerSplitMove() {
    var lockers = screenData.arcLockers || {};
    var dialogState = lockers.splitDialog;
    if (!dialogState) return;

    var numberInput = document.getElementById('arc-split-amount-input');
    var requestedAmount = normalizeArcLockerSplitAmount(numberInput && numberInput.value, dialogState.amount || 1, dialogState.maxAmount);
    dialogState.amount = requestedAmount;
    closeArcLockerSplitDialog(true);
    sendAction('moveArcLockerItem', {
        fromSide: dialogState.fromSide,
        slot: dialogState.slot,
        focusSide: lockers.focusSide === 'loadout' ? 'loadout' : 'main',
        toSide: dialogState.targetSide,
        targetSlot: null,
        requestedAmount: requestedAmount
    });
}

function getArcLockerDropPayloadFromTarget(targetEl) {
    var source = arcLockerDragState;
    if (!source || !targetEl || targetEl.nodeType !== 1) return null;

    var itemTarget = targetEl.closest('.arc-item-card');
    if (itemTarget) {
        var targetSide = itemTarget.getAttribute('data-arc-side') === 'loadout' ? 'loadout' : 'main';
        var targetSlot = Number(itemTarget.getAttribute('data-arc-slot') || 0);
        if (!targetSlot || (targetSide === source.fromSide && targetSlot === source.slot)) return null;
        return buildArcLockerMovePayload(source.fromSide, source.slot, source.focusSide, targetSide, targetSlot);
    }

    var zone = targetEl.closest('[data-arc-drop-side]');
    if (!zone) return null;

    var zoneSide = zone.getAttribute('data-arc-drop-side') === 'loadout' ? 'loadout' : 'main';
    if (zoneSide === source.fromSide) return null;
    return buildArcLockerMovePayload(source.fromSide, source.slot, source.focusSide, zoneSide, null);
}

function clearArcLockerDropTargets() {
    document.querySelectorAll('.is-arc-drop-target').forEach(function (el) {
        el.classList.remove('is-arc-drop-target');
    });
}

function clearArcLockerDraggingState() {
    document.querySelectorAll('.is-arc-dragging').forEach(function (el) {
        el.classList.remove('is-arc-dragging');
    });
}

function setArcLockerDragState(itemCard) {
    if (!itemCard) return false;
    arcLockerDragState = {
        fromSide: itemCard.getAttribute('data-arc-side') === 'loadout' ? 'loadout' : 'main',
        slot: Number(itemCard.getAttribute('data-arc-slot') || 0),
        focusSide: (screenData.arcLockers && screenData.arcLockers.focusSide) === 'loadout' ? 'loadout' : 'main'
    };
    clearArcLockerDraggingState();
    arcLockerDragSuppressUntil = Date.now() + ARC_LOCKER_DRAG_SUPPRESS_START_MS;
    itemCard.classList.add('is-arc-dragging');
    return true;
}

function setArcLockerDropHighlight(targetEl) {
    var payload = getArcLockerDropPayloadFromTarget(targetEl);
    clearArcLockerDropTargets();
    if (!payload) return null;

    var highlightTarget = targetEl.closest('.arc-item-card, [data-arc-drop-side]');
    if (highlightTarget) {
        highlightTarget.classList.add('is-arc-drop-target');
    }
    return payload;
}

function commitArcLockerDrop(targetEl) {
    var payload = getArcLockerDropPayloadFromTarget(targetEl);
    clearArcLockerDropTargets();
    clearArcLockerDraggingState();
    if (!payload) {
        arcLockerDragState = null;
        return null;
    }

    arcLockerDragSuppressUntil = Date.now() + ARC_LOCKER_DRAG_SUPPRESS_DROP_MS;
    sendAction('moveArcLockerItem', payload);
    arcLockerDragState = null;
    return payload;
}

document.addEventListener('dragstart', function (event) {
    var itemCard = event.target.closest('.arc-item-card');
    if (!itemCard || currentScreen !== 'arcLockers') return;
    event.preventDefault();
    arcLockerNativeDragActive = false;
    arcLockerPointerDragState = null;
});

document.addEventListener('dragover', function (event) {
    if (!arcLockerDragState) return;
    var payload = setArcLockerDropHighlight(event.target);
    if (!payload) return;

    event.preventDefault();
});

document.addEventListener('drop', function (event) {
    if (!arcLockerDragState) return;
    var payload = getArcLockerDropPayloadFromTarget(event.target);
    if (!payload) {
        clearArcLockerDropTargets();
        clearArcLockerDraggingState();
        arcLockerDragState = null;
        arcLockerNativeDragActive = false;
        return;
    }

    event.preventDefault();
    arcLockerNativeDragActive = false;
    commitArcLockerDrop(event.target);
});

document.addEventListener('dragend', function () {
    clearArcLockerDropTargets();
    clearArcLockerDraggingState();
    arcLockerDragState = null;
    arcLockerNativeDragActive = false;
    arcLockerPointerDragState = null;
    arcLockerDragSuppressUntil = Date.now() + ARC_LOCKER_DRAG_SUPPRESS_END_MS;
});

document.addEventListener('pointerdown', function (event) {
    var itemCard = event.target.closest('.arc-item-card');
    if (!itemCard || event.button !== 0) return;

    arcLockerPointerDragState = {
        itemCard: itemCard,
        startX: event.clientX,
        startY: event.clientY,
        activated: false
    };
});

document.addEventListener('pointermove', function (event) {
    if (!arcLockerPointerDragState || arcLockerNativeDragActive) return;

    if (!arcLockerPointerDragState.activated) {
        var deltaX = event.clientX - arcLockerPointerDragState.startX;
        var deltaY = event.clientY - arcLockerPointerDragState.startY;
        var dragDistanceSquared = (deltaX * deltaX) + (deltaY * deltaY);
        if (dragDistanceSquared < ARC_LOCKER_POINTER_DRAG_THRESHOLD_SQ) return;
        if (!setArcLockerDragState(arcLockerPointerDragState.itemCard)) {
            arcLockerPointerDragState = null;
            return;
        }
        arcLockerPointerDragState.activated = true;
    }

    var pointerTarget = document.elementFromPoint(event.clientX, event.clientY);
    if (!pointerTarget) {
        clearArcLockerDropTargets();
        return;
    }
    setArcLockerDropHighlight(pointerTarget);
    event.preventDefault();
});

document.addEventListener('pointerup', function (event) {
    if (!arcLockerPointerDragState) return;

    var wasActivated = arcLockerPointerDragState.activated;
    arcLockerPointerDragState = null;
    if (!wasActivated || arcLockerNativeDragActive || !arcLockerDragState) return;

    var candidateDropTarget = document.elementFromPoint(event.clientX, event.clientY);
    if (!candidateDropTarget) {
        clearArcLockerDropTargets();
        clearArcLockerDraggingState();
        arcLockerDragState = null;
        return;
    }
    commitArcLockerDrop(candidateDropTarget);
    event.preventDefault();
});

document.addEventListener('pointercancel', function () {
    if (!arcLockerPointerDragState) return;

    arcLockerPointerDragState = null;
    clearArcLockerDropTargets();
    clearArcLockerDraggingState();
    arcLockerDragState = null;
});

document.addEventListener('contextmenu', function (event) {
    var itemCard = event.target.closest('.arc-item-card');
    if (!itemCard || currentScreen !== 'arcLockers') return;

    event.preventDefault();
    openArcLockerSplitDialog(itemCard.getAttribute('data-arc-side'), itemCard.getAttribute('data-arc-slot'));
});

function pickArcLockerSection(primary, secondary, side) {
    if (primary && primary.side === side) return primary;
    if (secondary && secondary.side === side) return secondary;
    return primary || secondary || {};
}

function renderArcLockerSlotPlaceholder(label, extraClass) {
    return '<div class="arc-slot-placeholder' + (extraClass ? ' ' + extraClass : '') + '">' +
        '<span>' + esc(label || 'Boş') + '</span>' +
    '</div>';
}

function renderArcLockerItem(item, section, focusSide, options) {
    item = item || {};
    section = section || {};
    options = options || {};

    var layout = options.layout || 'stash';
    var moveTargetSide = section.side === 'loadout' ? 'main' : 'loadout';
    var moveTargetLabel = moveTargetSide === 'loadout' ? 'Baskın Çantası' : 'Kalıcı Depo';
    var imageUrl = arcItemImageUrl(item);
    var fallbackUrl = arcItemPlaceholder(item.label || item.name);
    var title = item.label || item.name || 'İsimsiz Eşya';
    var category = getArcLockerCategory(item);
    var categoryMeta = getArcLockerCategoryMeta(category);
    var tip = (item.description || (title + ' • Yuva #' + (item.slot || 0))) +
        ' • Sürükle-bırak ile stacklemeyi deneyebilir, tek tıkla ' + moveTargetLabel + ' tarafına aktarabilir veya sağ tıkla adedini ayırabilirsin.';
    var layoutClass = layout === 'loadout' ? ' arc-item-card-loadout' : ' arc-item-card-stash';
    var thumbClass = layout === 'loadout' ? ' arc-item-thumb-loadout' : ' arc-item-thumb-stash';
    var metaHtml = layout === 'loadout'
        ? '<div class="arc-item-meta arc-item-meta-loadout">' +
            '<div class="arc-item-name">' + esc(title) + '</div>' +
            '<div class="arc-item-slot">Yuva #' + esc(item.slot || 0) + ' • ' + esc(categoryMeta.label) + '</div>' +
        '</div>'
        : '<div class="arc-item-meta arc-item-meta-stash">' +
            '<div class="arc-item-name">' + esc(title) + '</div>' +
            '<div class="arc-item-code">' + esc(categoryMeta.label) + ' • Yuva #' + esc(item.slot || 0) + '</div>' +
        '</div>';

    return '<button class="arc-item-card' + layoutClass + (section.side === focusSide ? ' is-focused' : '') + '" type="button" ' +
        'draggable="false" ' +
        'onclick="sendAction(\'moveArcLockerItem\',' + arcMovePayload(section.side, item.slot, focusSide) + ')" ' +
        'data-arc-side="' + esc(section.side || 'main') + '" ' +
        'data-arc-slot="' + esc(item.slot || 0) + '" ' +
        'data-arc-category="' + esc(category) + '" ' +
        'data-arc-stackable="' + esc(!item.isWeapon ? 'true' : 'false') + '" ' +
        'data-tip="' + esc(tip) + '">' +
            '<div class="arc-item-thumb' + thumbClass + '">' +
                '<img src="' + esc(imageUrl) + '" alt="' + esc(title) + '"' +
                    ' data-fallback-src="' + esc(fallbackUrl) + '">' +
                '<span class="arc-item-count">x' + esc(formatArcItemCount(item.count || 0)) + '</span>' +
            '</div>' +
            metaHtml +
        '</button>';
}

function renderArcLockerSplitDialog(dialogState) {
    if (!dialogState) return '';

    var targetLabel = dialogState.targetSide === 'loadout' ? 'Baskın Çantası' : 'Kalıcı Depo';
    return '<div class="arc-split-overlay" data-tip="Sağ tıkla bu yığından taşınacak miktarı seçersin.">' +
        '<div class="dialog-card arc-split-dialog" role="dialog" aria-modal="true" aria-labelledby="arc-split-dialog-title" aria-describedby="arc-split-dialog-text">' +
            '<div class="dialog-icon">&#9986;</div>' +
            '<div id="arc-split-dialog-title" class="dialog-title">Yığını Ayır</div>' +
            '<div id="arc-split-dialog-text" class="dialog-text">' + esc(dialogState.itemName) + ' yığınından kaç adet ' + esc(targetLabel) + ' tarafına taşınsın?</div>' +
            '<div class="arc-split-amount-row">' +
                '<input id="arc-split-amount-range" class="arc-split-range" type="range" min="1" max="' + esc(dialogState.maxAmount) + '" value="' + esc(dialogState.amount) + '" aria-label="Taşınacak miktar kaydırıcısı" oninput="syncArcLockerSplitInputs(this)">' +
                '<input id="arc-split-amount-input" class="arc-split-input" type="number" min="1" max="' + esc(dialogState.maxAmount) + '" value="' + esc(dialogState.amount) + '" aria-label="Taşınacak miktar adedi" oninput="syncArcLockerSplitInputs(this)">' +
            '</div>' +
            '<div class="arc-split-counts">' +
                '<span id="arc-split-source-count">Kaynakta kalacak: x' + esc(Math.max(dialogState.totalCount - dialogState.amount, 0)) + '</span>' +
                '<span id="arc-split-target-count">Taşınacak: x' + esc(dialogState.amount) + '</span>' +
            '</div>' +
            '<div class="dialog-buttons">' +
                '<button class="btn" type="button" onclick="closeArcLockerSplitDialog()">İptal</button>' +
                '<button class="btn btn-primary" type="button" onclick="confirmArcLockerSplitMove()">Ayır ve Taşı</button>' +
            '</div>' +
        '</div>' +
    '</div>';
}

function renderArcLockerPreview(section) {
    section = section || {};
    var stats = getArcLockerSectionStats(section);
    var item = stats.items[0];

    if (!item) {
        return '<div class="arc-loadout-preview is-empty">' +
            '<div class="arc-loadout-preview-kicker">AKTİF SİLAH</div>' +
            '<div class="arc-loadout-preview-title">Henüz hazırlanmadı</div>' +
            '<div class="arc-loadout-preview-desc">Çantaya ilk eklediğin öğe burada büyük önizleme olarak görünür.</div>' +
        '</div>';
    }

    var imageUrl = arcItemImageUrl(item);
    var fallbackUrl = arcItemPlaceholder(item.label || item.name);
    return '<div class="arc-loadout-preview">' +
        '<div class="arc-loadout-preview-kicker">AKTİF ÖNİZLEME</div>' +
        '<div class="arc-loadout-preview-title">' + esc(item.label || item.name || 'Eşya') + '</div>' +
        '<div class="arc-loadout-preview-card">' +
            '<img src="' + esc(imageUrl) + '" alt="' + esc(item.label || item.name || 'Eşya') + '"' +
                ' data-fallback-src="' + esc(fallbackUrl) + '">' +
        '</div>' +
        '<div class="arc-loadout-preview-desc">Yuva #' + esc(item.slot || 0) + ' • x' + esc(item.count || 0) + ' adet hazır. Öğeyi tek tıkla taşıyabilir, sürükleyip başka bir stack üstüne bırakabilir veya sağ tıkla bölebilirsin.</div>' +
    '</div>';
}

function renderArcMainLockerPanel(section, focusSide) {
    section = section || {};
    var stats = getArcLockerSectionStats(section);
    var filteredItems = getArcLockerFilteredItems(section);
    var activeCategory = getArcLockerCategoryMeta(getArcLockerActiveCategory());
    var helperText = section.helperText || 'Burası kalıcı depon. İçindekiler baskın dışında da sende kalır.';
    var sideLabel = section.side === focusSide ? 'AKTİF DEPO' : 'PASİF DEPO';
    var html = '<section class="arc-locker-panel arc-locker-panel-stash' + (section.side === focusSide ? ' is-focused' : '') + '">' +
        '<div class="arc-locker-panel-top">' +
            '<div>' +
                '<div class="arc-locker-panel-kicker">STASH</div>' +
                '<div class="arc-locker-panel-title">' + esc(section.title || section.label || 'Kalıcı Depo') + '</div>' +
                '<div class="arc-locker-panel-subtitle">' + esc(helperText) + '</div>' +
            '</div>' +
            '<div class="arc-locker-panel-badges">' +
                '<span class="arc-locker-badge">' + esc(stats.usedSlots) + '/' + esc(stats.totalSlots || stats.usedSlots || 0) + '</span>' +
                '<span class="arc-locker-badge arc-locker-badge-muted">' + esc(sideLabel) + '</span>' +
            '</div>' +
        '</div>' +
        '<div class="arc-locker-stash-shell">' +
            renderArcLockerCategoryRail(section) +
            '<div class="arc-locker-stash-content">' +
                '<div class="arc-locker-stash-toolbar">' +
                    '<div class="arc-locker-pill">&#9776; ' + esc(activeCategory.label) + '</div>' +
                    '<div class="arc-locker-pill">' + esc(stats.totalItems) + ' eşya</div>' +
                    '<div class="arc-locker-pill">' + esc(filteredItems.length) + ' görünür slot</div>' +
                    '<div class="arc-locker-pill">' + esc(stats.freeSlots) + ' boş yuva</div>' +
                '</div>' +
                '<div class="arc-locker-stash-grid" data-arc-drop-side="' + esc(section.side || 'main') + '">';

    if (filteredItems.length) {
        filteredItems.forEach(function (item) {
            html += renderArcLockerItem(item, section, focusSide, { layout: 'stash' });
        });
    } else {
        html += '<div class="arc-locker-stash-empty">' +
            emptyState('&#128230;', activeCategory.key === 'all' ? 'Kalıcı depon şu anda boş.' : (activeCategory.label + ' kategorisinde eşya yok.')) +
        '</div>';
    }

    html += '</div></div></div></section>';
    return html;
}

function renderArcLoadoutPanel(section, focusSide) {
    section = section || {};
    var stats = getArcLockerSectionStats(section);
    var helperText = section.helperText || 'Buraya koyduğun ekipman baskın girişinde üstüne verilir.';
    var defaultBackpackSlots = 24;
    var visibleBackpackSlots = Math.max(stats.items.length, stats.totalSlots || defaultBackpackSlots);
    var placeholderCount = Math.max(visibleBackpackSlots - stats.items.length, 0);
    var html = '<section class="arc-locker-panel arc-locker-panel-loadout' + (section.side === focusSide ? ' is-focused' : '') + '">' +
        '<div class="arc-locker-panel-top arc-locker-panel-top-loadout">' +
            '<div>' +
                '<div class="arc-locker-panel-kicker">LOADOUT</div>' +
                '<div class="arc-locker-panel-title">' + esc(section.title || section.label || 'Baskın Çantası') + '</div>' +
                '<div class="arc-locker-panel-subtitle">' + esc(helperText) + '</div>' +
            '</div>' +
            '<div class="arc-locker-loadout-stats">' +
                '<span class="arc-locker-badge">' + esc(stats.usedSlots) + '/' + esc(stats.totalSlots || stats.usedSlots || 0) + ' yuva</span>' +
                '<span class="arc-locker-badge arc-locker-badge-muted">' + esc(stats.totalItems) + ' eşya</span>' +
            '</div>' +
        '</div>' +
        '<div class="arc-loadout-layout">' +
            '<div class="arc-loadout-column arc-loadout-column-preview">' +
                renderArcLockerPreview(section) +
            '</div>' +
            '<div class="arc-loadout-column arc-loadout-column-main">' +
                '<div class="arc-loadout-group arc-loadout-group-backpack">' +
                    '<div class="arc-loadout-group-header"><span>BACKPACK</span><span>' + esc(stats.usedSlots) + '/' + esc(stats.totalSlots || stats.usedSlots || 0) + '</span></div>' +
                    '<div class="arc-loadout-drop-helper">İtemi başka bir itemin üstüne bırakıp stacklemeyi dene. Sağ tık tam yığından parça ayırır; silahlar asla stacklenmez.</div>' +
                    '<div class="arc-loadout-backpack-grid" data-arc-drop-side="' + esc(section.side || 'loadout') + '">';

    stats.items.forEach(function (item) {
        html += renderArcLockerItem(item, section, focusSide, { layout: 'loadout' });
    });
    for (var i = 0; i < placeholderCount; i++) {
        html += renderArcLockerSlotPlaceholder('Boş');
    }

    html += '</div></div></div>' +
        '</div>' +
    '</section>';

    return html;
}

function getArcLoadoutPresentation(state) {
    state = state || {};
    var loadoutState = state.arcLoadoutState || {};
    var stacks = Number(state.arcLoadoutStacks || 0);

    if (loadoutState.isReady) {
        return {
            badge: 'ÇANTA HAZIR x' + esc(String(stacks)),
            title: 'Baskın çantası hazır',
            detail: 'Buraya koyduğun ekipman baskına girerken üstüne verilecek.',
            statusClass: 'ok'
        };
    }

    if (loadoutState.usesFallback) {
        return {
            badge: 'ÇANTA BOŞ • YEDEK PAKET',
            title: 'Baskın çantası boş',
            detail: 'Hazır ekipmanın yoksa varsayılan başlangıç paketi verilecek.',
            statusClass: 'warn'
        };
    }

    return {
        badge: 'ÇANTA BOŞ',
        title: 'Baskın çantası boş',
        detail: loadoutState.helperText || 'Bu baskın için önceden ekipman hazırlaman gerekiyor.',
        statusClass: 'error'
    };
}

function renderArcCheckChip(check) {
    check = check || {};
    return '<div class="arc-check-chip status-' + esc(check.status || 'ok') + '">' +
        '<div class="arc-check-title">' + esc(check.title || 'Kontrol') + '</div>' +
        '<div class="arc-check-detail">' + esc(check.detail || '') + '</div>' +
    '</div>';
}

function renderArcPreflightSummary(state) {
    state = state || {};
    var summary = state.arcSummary || {};
    var loadoutUi = getArcLoadoutPresentation(state);
    var blockers = summary.blockers || [];
    var hiddenCheckKeys = ['distance', 'inventory', 'extraction'];
    var checks = (summary.checks || []).filter(function (check) {
        return !check || hiddenCheckKeys.indexOf(check.key) === -1;
    });
    var html = '<div class="arc-preflight-card">' +
        '<div class="arc-preflight-header">' +
            '<div>' +
                '<div class="section-title">&#128737; Baskın Kontrol Özeti</div>' +
                '<div class="menu-item-desc">Baskına girmeden önce hangi hazırlıkların tamam, hangilerinin eksik olduğunu burada gör.</div>' +
            '</div>' +
        '</div>' +
        '<div class="req-chips">' +
            '<span class="req-chip"><span class="req-chip-amount">' + esc(loadoutUi.title) + '</span>çanta</span>' +
            '<span class="req-chip"><span class="req-chip-amount">' + esc(summary.canDeploy ? 'Hazır' : 'Eksik Var') + '</span>baskın</span>' +
            '<span class="req-chip"><span class="req-chip-amount">' + esc(state.disconnectPolicyLabel || 'Güvenli Dönüş') + '</span>kopma durumu</span>' +
            '<span class="req-chip"><span class="req-chip-amount">' + esc(state.allowPersonalInventory ? 'Açık' : 'Kapalı') + '</span>TAB çantası</span>' +
        '</div>' +
        '<div class="arc-preflight-detail">' + esc(loadoutUi.detail) + '</div>';

    if (checks.length) {
        html += '<div class="arc-check-grid">';
        checks.forEach(function (check) {
            html += renderArcCheckChip(check);
        });
        html += '</div>';
    }

    if (blockers.length) {
        html += '<div class="arc-blocker-list">';
        blockers.forEach(function (blocker) {
            html += '<div class="arc-blocker-item">&#9888; ' + esc(blocker) + '</div>';
        });
        html += '</div>';
    } else {
        html += '<div class="arc-blocker-list is-clear"><div class="arc-blocker-item">&#9989; Baskına girmek için kritik bir eksik görünmüyor.</div></div>';
    }

    return html + '</div>';
}

// ═══════════════════════════════════════════════════════════════════════════
//  SCREENS
// ═══════════════════════════════════════════════════════════════════════════

// ── Main Menu ──────────────────────────────────────────────────────────────
function showMenu(state) {
    state = state || {};
    currentScreen = 'menu';
    screenData.menuState = state;
    ensureMenuSelections(state);
    var view = syncMenuView(state);
    var panel = view.panel ? getMenuPanelDefinition(view.panel) : null;
    var isArcPanel = view.section === 'arc';
    var operatorCards = isArcPanel ? [
        {
            label: 'KARAKTER',
            value: state.playerName || 'Bilinmeyen Operatif',
            valuePct: clamp(((state.playerName || 'Bilinmeyen Operatif').length || 1) * 7, 24, 100)
        },
        {
            label: 'MOD',
            value: isArcPanel ? 'ARC Baskını' : 'Hayatta Kalma',
            valuePct: 100
        },
        {
            label: 'YÜK',
            value: isArcPanel ? getArcLoadoutPresentation(state).title : (state.upgradeLabel || 'Standart Paket'),
            valuePct: isArcPanel ? (state.arcLoadoutReady ? 92 : 44) : (state.upgradeLabel === 'Standart Paket' ? 36 : 82)
        },
        {
            label: 'TAKIM',
            value: state.lobbyStatus || 'Tek Başına',
            valuePct: state.hasLobby ? (state.isLeader ? 88 : 74) : 28
        }
    ] : buildOperatorCards();
    setMainNavigationVisible(true);
    renderMenuSidebar(buildSidebarHtml(state, view));
    setBreadcrumb(panel ? ('Operasyon Menüsü / ' + (panel.label || 'Ana Menü')) : 'Operasyon Menüsü');
    setHudState({
        operatorCards: operatorCards,
        showLobbyMembers: state.hasLobby === true,
        lobbyMembers: state.lobbyMembers || [],
        health: clamp(MAIN_MENU_BASE_HEALTH + ((state.userLevel || 1) * MAIN_MENU_HEALTH_PER_LEVEL), 0, 100),
        radiation: view.section === 'arc' ? 41 : state.isLeader ? 34 : state.isMember ? 42 : 18,
        inventoryPct: view.section === 'arc' ? (state.arcLoadoutReady ? 82 : 46) : state.hasLobby ? 66 : 50,
        inventoryText: view.section === 'arc'
            ? String(state.arcLoadoutItems || 0) + '/' + String(state.arcLoadoutStacks || 0)
            : (state.hasLobby ? '04/06' : '03/06'),
        signal: state.hasLobby ? 86 : 71,
        signalText: state.hasLobby ? 'TAKIM' : 'TEK',
        briefTitle: panel ? (panel.label || 'Operasyon Hazır') : 'Hazırlık Ekranı',
        briefText: panel ? (panel.desc || 'Sol menüden seç, açılan pencereden yönet.') : 'İçerik otomatik açılmaz; soldaki menüden ekran seç.',
        briefTag: view.section === 'arc' ? 'ARC' : view.section === 'survival' ? 'SURV' : 'LOBİ',
        progress: state.hasLobby ? 54 : 36,
        slotsFilled: state.hasLobby ? 4 : 3,
        hideMissionBrief: true
    });
    setContent(renderMenuPanel(state, view));
}

function showArcLockers(data) {
    data = data || {};
    hideMainNavigation();
    var previousData = screenData.arcLockers || {};
    data.activeCategory = previousData.activeCategory || data.activeCategory || 'all';
    screenData.arcLockers = data;

    var focusSide = data.focusSide === 'loadout' ? 'loadout' : 'main';
    var nextFocus = focusSide === 'loadout' ? 'main' : 'loadout';
    var mainSection = pickArcLockerSection(data.focused, data.paired, 'main');
    var loadoutSection = pickArcLockerSection(data.focused, data.paired, 'loadout');
    var focusedLabel = focusSide === 'loadout'
        ? (loadoutSection.label || loadoutSection.title || 'ARC Baskın Çantası')
        : (mainSection.label || mainSection.title || 'ARC Kalıcı Depo');
    var nextFocusLabel = nextFocus === 'loadout' ? 'Baskın Çantası' : 'Kalıcı Depo';
    var html = backBtn();

    setBreadcrumb('ARC Depo Yönetimi');
    currentScreen = 'arcLockers';

    html += '<section class="arc-locker-shell">' +
        '<div class="arc-locker-notice" data-tip="Bu ekranda kişisel çantan açılmaz; iki ARC deposu arasında taşıma, stackleme ve sağ tıkla ayırma yaparsın.">' +
            '<div class="arc-locker-notice-copy">' +
                '<div class="arc-locker-panel-kicker">INVENTORY</div>' +
                '<div class="menu-item-title">Odak: ' + esc(focusedLabel) + '</div>' +
                '<div class="menu-item-desc">Kalıcı depo baskın dışında da sende kalır. Baskın çantası ise girişte üstüne verilecek ekipmanı tutar. ' + esc((data.transferSupport && data.transferSupport.helperText) || 'Sol tık sürükle-bırak ile stackleyebilir, sağ tık ile yığından parça ayırabilirsin.') + '</div>' +
            '</div>' +
            '<div class="arc-locker-toolbar">' +
                actionBtn('Yenile', 'refreshArcLockers', { focusSide: focusSide }, 'İki ARC deposundaki listeyi yeniden yükle.') +
                actionBtn(nextFocusLabel + ' Odağına Geç', 'swapArcLockerFocus', { focusSide: nextFocus }, 'Üstte görünen depo bölümünü değiştir.') +
            '</div>' +
        '</div>' +
        '<div class="arc-locker-layout">' +
            renderArcMainLockerPanel(mainSection, focusSide) +
            renderArcLoadoutPanel(loadoutSection, focusSide) +
        '</div>' +
        renderArcLockerSplitDialog(data.splitDialog) +
    '</section>';

    setContent(html);
}

// ── Market ─────────────────────────────────────────────────────────────────
function showMarket(data) {
    data = data || {};
    hideMainNavigation();
    currentScreen = 'market';
    screenData.upgrades = data.upgrades || [];
    setBreadcrumb('Operasyon Menüsü / Market');
    setHudState({
        health: 82,
        radiation: 27,
        inventoryPct: 58,
        inventoryText: '03/06',
        signal: 90,
        signalText: 'TEDARIK',
        briefTitle: 'Saha Marketi',
        briefText: 'Güçlendirmeleri satın al ve bir sonraki çatışma için avantaj kazan.',
        briefTag: 'PAZAR',
        progress: 68,
        slotsFilled: 3
    });

    var html = backBtn();
    html += '<div class="section-header"><div class="section-title">&#128722; Güçlendirmeler</div></div>';

    if (screenData.upgrades.length === 0) {
        html += emptyState('&#127978;', 'Satın alınabilir güçlendirme bulunamadı.');
        setContent(html);
        return;
    }

    for (var i = 0; i < screenData.upgrades.length; i++) {
        var upg = screenData.upgrades[i];
        var power = clamp(35 + (i * 14), 18, 96);
        html += '<div class="card" data-tip="' + esc((upg.label || 'Yükseltme') + ': kredi kullanarak kalıcı saha desteği sağlar.') + '">' +
            '<div class="card-header">' +
                '<div class="card-title">' + esc(upg.label) + '</div>' +
                '<div class="price-tag">$' + fmtNum(upg.price) + '</div>' +
            '</div>' +
            '<div class="card-desc">Satın alındığında takımına doğrudan saha avantajı sağlar.</div>' +
            screenMeter('Etkililik', power) +
            '<div class="card-footer"><span class="menu-item-badge price">Kredi</span>' +
                '<button class="btn btn-primary" type="button" onclick="buyUpgrade(' + i + ')">&#128176; Satin Al</button>' +
            '</div>' +
        '</div>';
    }

    setContent(html);
}

function buyUpgrade(idx) {
    sendAction('buyUpgrade', screenData.upgrades[idx]);
}

var ARC_CRAFT_CATEGORIES = [
    { key: 'ammo', label: 'Mermi Craft Yeri', icon: '&#128165;', description: 'Şarjör ve baskın boyunca harcayacağın cephane paketleri burada hazırlanır.' },
    { key: 'weapon', label: 'Silah Craft Yeri', icon: '&#128299;', description: 'Blueprint ve ağır parçaları birleştirerek operasyon silahlarını üret.' },
    { key: 'health', label: 'Sağlık Eşyaları Craft Yeri', icon: '&#10010;', description: 'Bandaj, medikal kit ve hayatta kalma desteklerini ayrı bölümde takip et.' },
    { key: 'material', label: 'Malzeme Craft Yeri', icon: '&#128736;', description: 'Tamir ve yardımcı saha ekipmanları için gereken parçaları burada yönet.' }
];
var CRAFT_READY_METER_VALUE = 94;
var CRAFT_METER_BASE_VALUE = 36;
var CRAFT_METER_INCREMENT = 9;
var CRAFT_METER_MIN = 18;
var CRAFT_METER_MAX = 82;

function getCraftOwnedText(requirement, isArcCraft) {
    var ownedAmount = Number((requirement && requirement.ownedAmount) || 0);
    var neededAmount = Number((requirement && requirement.amount) || 0);
    return (isArcCraft ? 'Depoda: ' : 'Sende: ') + ownedAmount + '/' + neededAmount;
}

function renderCraftRequirementList(recipe, isArcCraft) {
    if (!recipe.requirements || recipe.requirements.length === 0) return '';

    var reqs = '<div class="requirements"><div class="req-title">Gereken Parçalar</div><div class="req-chips">';
    for (var j = 0; j < recipe.requirements.length; j++) {
        var requirement = recipe.requirements[j] || {};
        reqs += '<span class="req-chip' + (requirement.isMet ? ' is-met' : ' is-missing') + '">' +
            '<span class="req-chip-main">' +
                '<span class="req-chip-amount">x' + esc(String(requirement.amount || 0)) + '</span>' +
                '<span class="req-chip-name">' + esc(requirement.itemLabel || requirement.item || 'Parça') + '</span>' +
            '</span>' +
            '<span class="req-chip-owned">' + esc(getCraftOwnedText(requirement, isArcCraft)) + '</span>' +
        '</span>';
    }

    return reqs + '</div></div>';
}

function renderCraftCard(recipe, recipeIndex, isArcCraft) {
    var maxCraftable = Math.max(Math.floor(Number(recipe.maxCraftable) || 0), 0);
    var canCraft = recipe.ready === true && maxCraftable > 0;
    var meterValue = recipe.ready
        ? CRAFT_READY_METER_VALUE
        : clamp(CRAFT_METER_BASE_VALUE + (recipeIndex * CRAFT_METER_INCREMENT), CRAFT_METER_MIN, CRAFT_METER_MAX);
    return '<div class="card" data-tip="' + esc((recipe.label || recipe.header || 'Tarif') + ': gerekli malzemeler tamamlandığında üretilebilir.') + '">' +
        '<div class="card-header">' +
            '<div class="card-title">' + esc(recipe.header || recipe.label) + '</div>' +
            '<span class="menu-item-badge">x' + esc(String(recipe.amount || 0)) + '</span>' +
        '</div>' +
        (recipe.txt ? '<div class="card-desc">' + esc(recipe.txt) + '</div>' : '<div class="card-desc">Saha kullanımı için hızlıca hazırlanabilen ekipman paketi.</div>') +
        screenMeter(recipe.ready ? 'Hazır' : 'Eksik Parça', meterValue) +
        renderCraftRequirementList(recipe, isArcCraft) +
        '<div class="card-footer"><span class="menu-item-badge' + (recipe.ready ? ' ok' : ' warn') + '">' + esc(recipe.ready ? 'HAZIR' : 'EKSİK') + '</span>' +
            '<button class="btn ' + (canCraft ? 'btn-primary' : 'btn-danger') + ' btn-craft-action" type="button"' +
                (canCraft ? ' onclick="craftItem(' + recipeIndex + ')"' : ' disabled aria-disabled="true"') +
            '>&#9878; Üret / Birleştir</button>' +
        '</div>' +
    '</div>';
}

function renderArcCraftSections(recipes) {
    var groups = {};
    var html = '';

    for (var i = 0; i < recipes.length; i++) {
        var categoryKey = (recipes[i] && recipes[i].category) || 'material';
        if (!groups[categoryKey]) groups[categoryKey] = [];
        groups[categoryKey].push({ recipe: recipes[i], index: i });
    }

    for (var j = 0; j < ARC_CRAFT_CATEGORIES.length; j++) {
        var category = ARC_CRAFT_CATEGORIES[j];
        var entries = groups[category.key] || [];

        html += '<div class="craft-category-block">' +
            '<div class="craft-category-header">' +
                '<div class="craft-category-title-wrap">' +
                    '<div class="craft-category-kicker">ARC ATÖLYESİ</div>' +
                    '<div class="craft-category-title">' + category.icon + ' ' + esc(category.label) + '</div>' +
                '</div>' +
                '<div class="craft-category-count">' + esc(String(entries.length)) + ' tarif</div>' +
            '</div>' +
            '<div class="craft-category-desc">' + esc(category.description) + '</div>';

        if (entries.length === 0) {
            html += '<div class="craft-category-empty">Bu bölüm için tanımlı tarif bulunmuyor.</div>';
        } else {
            for (var k = 0; k < entries.length; k++) {
                html += renderCraftCard(entries[k].recipe, entries[k].index, true);
            }
        }

        html += '</div>';
    }

    return html;
}

function closeCraftQuantityDialog(skipRender) {
    screenData.craftDialog = null;
    if (!skipRender) {
        renderCraftScreen();
    }
}

function normalizeCraftQuantity(rawValue, fallbackValue, maxAmount) {
    if (Number(maxAmount || 0) < 1) return 0;
    var nextRawValue = (rawValue == null || rawValue === '') ? fallbackValue : rawValue;
    var parsedValue = Number(nextRawValue);
    if (!isFinite(parsedValue)) {
        parsedValue = Number(fallbackValue);
    }
    return clamp(
        Math.floor(parsedValue || 1),
        1,
        Number(maxAmount || 1)
    );
}

function syncCraftQuantityInputs(source) {
    var dialogState = screenData.craftDialog;
    if (!dialogState) return;

    var nextValue = normalizeCraftQuantity(source && source.value, dialogState.amount || 1, dialogState.maxAmount);
    dialogState.amount = nextValue;

    var rangeInput = document.getElementById('craft-quantity-range');
    var numberInput = document.getElementById('craft-quantity-input');
    var craftCount = document.getElementById('craft-quantity-count');
    var totalOutput = document.getElementById('craft-total-output');

    if (rangeInput && rangeInput !== source) rangeInput.value = String(nextValue);
    if (numberInput && numberInput !== source) numberInput.value = String(nextValue);
    if (craftCount) craftCount.textContent = 'Üretim adedi: x' + String(nextValue);
    if (totalOutput) totalOutput.textContent = 'Toplam çıktı: x' + String(nextValue * dialogState.outputAmount);
}

function renderCraftQuantityDialog(dialogState) {
    if (!dialogState) return '';

    var helperText = dialogState.maxAmount > 0
        ? 'Bu tariften şu an en fazla ' + dialogState.maxAmount + ' kez üretebilirsin. Her üretimde x' + dialogState.outputAmount + ' gelir.'
        : 'Bu tarif için yeterli malzemen yok. Gerekli parçaları tamamladıktan sonra üretim adedini seçebilirsin.';
    var controlsHtml = dialogState.maxAmount > 0
        ? '<div class="arc-split-amount-row">' +
            '<input id="craft-quantity-range" class="arc-split-range" type="range" min="1" max="' + esc(dialogState.maxAmount) + '" value="' + esc(dialogState.amount) + '" aria-label="Üretim adedi kaydırıcısı" oninput="syncCraftQuantityInputs(this)">' +
            '<input id="craft-quantity-input" class="arc-split-input" type="number" min="1" max="' + esc(dialogState.maxAmount) + '" value="' + esc(dialogState.amount) + '" aria-label="Üretim adedi" oninput="syncCraftQuantityInputs(this)">' +
        '</div>' +
        '<div class="arc-split-counts">' +
            '<span id="craft-quantity-count">Üretim adedi: x' + esc(dialogState.amount) + '</span>' +
            '<span id="craft-total-output">Toplam çıktı: x' + esc(dialogState.amount * dialogState.outputAmount) + '</span>' +
        '</div>'
        : '<div class="craft-quantity-empty">Maksimum üretim: x0</div>';

    return '<div class="arc-split-overlay" data-tip="Kaç kez üreteceğini seçerek toplam çıktıyı anında görebilirsin." title="Kaç kez üreteceğini seçerek toplam çıktıyı anında görebilirsin.">' +
        '<div class="dialog-card arc-split-dialog" role="dialog" aria-modal="true" aria-labelledby="craft-quantity-dialog-title" aria-describedby="craft-quantity-dialog-text">' +
            '<div class="dialog-icon">&#128296;</div>' +
            '<div id="craft-quantity-dialog-title" class="dialog-title">Üretim Miktarı</div>' +
            '<div id="craft-quantity-dialog-text" class="dialog-text">' + esc(dialogState.recipeName) + ' için miktarı seç. ' + esc(helperText) + '</div>' +
            controlsHtml +
            '<div class="craft-quantity-max">Maksimum toplam çıktı: x' + esc(dialogState.maxAmount * dialogState.outputAmount) + '</div>' +
            '<div class="dialog-buttons">' +
                '<button class="btn" type="button" onclick="closeCraftQuantityDialog()">İptal</button>' +
                '<button class="btn btn-primary" type="button"' + (dialogState.maxAmount > 0 ? ' onclick="confirmCraftItem()"' : ' disabled aria-disabled="true"') + '>Üretimi Başlat</button>' +
            '</div>' +
        '</div>' +
    '</div>';
}

function renderCraftScreen() {
    var isArcCraft = screenData.craftSource.key === 'arc_main' || screenData.craftSource.key === 'arc_loadout';
    setBreadcrumb(isArcCraft ? 'Operasyon Menüsü / ARC Atölyesi' : 'Operasyon Menüsü / Atölye');
    setHudState({
        health: 78,
        radiation: 18,
        inventoryPct: 74,
        inventoryText: '05/06',
        signal: 82,
        signalText: 'ATÖLYE',
        briefTitle: isArcCraft ? 'ARC Atölyesi Hazır' : 'Atölye Hazır',
        briefText: isArcCraft
            ? 'Kalıcı depodaki lootları kullan, operasyon öncesi ekipmanını craft et ve sonucu aynı depoda sakla.'
            : 'Tarifleri incele, parçaları topla ve ekipmanını atölyede birleştir.',
        briefTag: isArcCraft ? 'ARC' : 'ATÖLYE',
        progress: 72,
        slotsFilled: 5
    });

    var html = backBtn();
    html += '<div class="section-header"><div class="section-title">&#128296; ' + esc(isArcCraft ? 'ARC Atölye Tarifleri' : 'Atölye Tarifleri') + '</div></div>';

    if (screenData.craftSource.label) {
        html += '<div class="arc-locker-notice" data-tip="' + esc(screenData.craftSource.helperText || 'Seçilen ARC deposundaki lootlar craft için kullanılacak.') + '">' +
            '<div class="menu-item-icon">&#128451;</div>' +
            '<div class="menu-item-content">' +
                '<div class="menu-item-title">Malzeme Kaynağı: ' + esc(screenData.craftSource.label) + '</div>' +
                '<div class="menu-item-desc">' + esc(screenData.craftSource.helperText || 'Üretilen eşya aynı depoya geri eklenir.') + '</div>' +
            '</div>' +
        '</div>';
    }

    if (screenData.recipes.length === 0) {
        html += emptyState('&#128296;', 'Atölyede birleştirilebilecek tarif bulunamadı.');
        setContent(html);
        return;
    }

    if (isArcCraft) {
        html += renderArcCraftSections(screenData.recipes);
    } else {
        for (var i = 0; i < screenData.recipes.length; i++) {
            html += renderCraftCard(screenData.recipes[i], i, false);
        }
    }

    html += renderCraftQuantityDialog(screenData.craftDialog);
    setContent(html);
}

// ── Craft ──────────────────────────────────────────────────────────────────
function showCraft(data) {
    data = data || {};
    hideMainNavigation();
    currentScreen = 'craft';
    screenData.recipes = data.recipes || [];
    screenData.craftSource = {
        key: data.sourceKey || '',
        label: data.sourceLabel || '',
        helperText: data.helperText || ''
    };
    screenData.craftDialog = null;
    renderCraftScreen();
}

function craftItem(idx) {
    var r = screenData.recipes[idx];
    if (!r) return;
    var maxCraftable = Math.max(Math.floor(Number(r.maxCraftable) || 0), 0);
    if (r.ready !== true || maxCraftable < 1) return;
    screenData.craftDialog = {
        recipeIndex: idx,
        recipeName: r.label || r.header || 'Tarif',
        amount: maxCraftable > 0 ? 1 : 0,
        maxAmount: maxCraftable,
        outputAmount: Math.max(Math.floor(Number(r.amount) || 0), 0)
    };
    playUiTone(maxCraftable > 0 ? 'confirm' : 'alert');
    renderCraftScreen();
}

function confirmCraftItem() {
    var dialogState = screenData.craftDialog;
    if (!dialogState) return;

    var r = screenData.recipes[dialogState.recipeIndex];
    if (!r) {
        closeCraftQuantityDialog();
        return;
    }

    var numberInput = document.getElementById('craft-quantity-input');
    var requestedAmount = normalizeCraftQuantity(numberInput && numberInput.value, dialogState.amount || 1, dialogState.maxAmount);
    if (requestedAmount < 1) {
        pushArcNotify({
            type: 'warning',
            title: 'Üretim Başlatılamadı',
            message: 'Bu tarif için önce gerekli parçaları tamamlaman gerekiyor.',
            duration: 3200
        });
        return;
    }

    dialogState.amount = requestedAmount;
    closeCraftQuantityDialog(true);
    playMechanicalTone('workshop');
    sendAction('craftItem', {
        item:         r.item,
        amount:       r.amount,
        label:        r.label || r.header,
        multiplier:   requestedAmount,
        stashId:      r.stashId
    });
}

// ── Stages ─────────────────────────────────────────────────────────────────
function showStages(data) {
    data = data || {};
    hideMainNavigation();
    currentScreen = 'stages';
    screenData.stages = data.stages || [];
    screenData.selectedModeId = data.modeId || 'classic';
    var menuState = screenData.menuState || {};
    var isArcMode = screenData.selectedModeId === 'arc_pvp';
    var operatorCards = isArcMode ? [
        {
            label: 'KARAKTER',
            value: menuState.playerName || 'Bilinmeyen Operatif',
            valuePct: clamp(((menuState.playerName || 'Bilinmeyen Operatif').length || 1) * 7, 24, 100)
        },
        {
            label: 'MOD',
            value: 'ARC Baskını',
            valuePct: 100
        },
        {
            label: 'YAPI',
            value: 'Sabit Konfigürasyon',
            valuePct: 100
        },
        {
            label: 'TAKIM',
            value: menuState.lobbyStatus || 'Solo',
            valuePct: menuState.hasLobby ? (menuState.isLeader ? 88 : 74) : 28
        }
    ] : undefined;
    setBreadcrumb(isArcMode ? 'ARC Menüsü / Baskın Başlat' : 'Operasyon Menüsü / Bölge Seçimi');
    setHudState({
        operatorCards: operatorCards,
        health: 88,
        radiation: 39,
        inventoryPct: 62,
        inventoryText: '04/06',
        signal: 94,
        signalText: 'HEDEF',
        briefTitle: data.modeLabel || 'Bölge Seçimi',
        briefText: isArcMode
            ? 'ARC baskını sabit ayarlarla başlar. Takımın hazırsa operasyona hemen çıkabilirsin.'
            : 'Zorluk katsayılarını incele ve takımına uygun bölgeyi seç.',
        briefTag: isArcMode ? 'ARC' : 'BÖLGE',
        progress: 81,
        slotsFilled: 4
    });

    var html = backBtn();
    html += '<div class="section-header"><div class="section-title">&#128205; ' + esc(data.modeLabel || 'Bölgeler') + '</div></div>';

    if (screenData.stages.length === 0) {
        html += emptyState('&#127757;', 'Seçilebilir bölge bulunamadı.');
        setContent(html);
        return;
    }

    if (isArcMode) {
        html += '<div class="stage-grid">' +
            '<button class="stage-card" type="button" onclick="selectStage(0)" data-tip="ARC baskınında bölge seçimi kapalıdır; operasyon başladığında uygun deployment bölgesi rastgele belirlenir.">' +
                '<div class="stage-card-inner">' +
                    '<div class="stage-card-top"><span class="stage-chip">&#127920; ARC</span><span class="stage-chip">RASTGELE</span></div>' +
                    '<div><div class="stage-card-title">Rastgele Konuşlandırma</div><div class="stage-card-desc">ARC baskını sabit kurallarla başlar ve sistem seni uygun bir baskın bölgesine otomatik yerleştirir.</div></div>' +
                    '<div class="stage-card-footer"><span class="stage-chip muted">Otomatik Seçim</span><span class="stage-action">Baskını Başlat</span></div>' +
                '</div>' +
            '</button>' +
        '</div>';
        setContent(html);
        return;
    }

    html += '<div class="stage-grid">';
    for (var i = 0; i < screenData.stages.length; i++) {
        var s = screenData.stages[i];
        var cardClass = 'stage-card' + (s.locked ? ' locked' : '');
        var actionText = s.locked ? 'Kilitli' : (isArcMode ? 'Baskını Başlat' : 'Operasyonu Başlat');
        var difficulty = isArcMode ? 'Sabit Konfigürasyon' : (s.multiplier >= 1.5 ? 'Yüksek Risk' : s.multiplier >= 1.2 ? 'Orta Risk' : 'Düşük Risk');
        var tipText = s.locked
            ? (s.label + ': bu bölge kilitli ve seçilemez.')
            : (isArcMode
                ? (s.label + ': sabit ARC ayarlarıyla hemen başlatılır.')
                : (s.label + ': seçildiğinde operasyon x' + s.multiplier + ' zorluk çarpanı ile başlar.'));

        if (s.locked) {
            html += '<div class="' + cardClass + '" style="' + stageCardArt(s, i) + '" data-tip="' + esc(tipText) + '">' +
                '<div class="stage-card-inner">' +
                    '<div class="stage-card-top"><span class="stage-chip locked">&#128274; Kilitli</span><span class="stage-chip">x' + s.multiplier + '</span></div>' +
                    '<div><div class="stage-card-title">' + esc(s.label) + '</div><div class="stage-card-desc">Bu bölge henüz kullanıma açık değil.</div></div>' +
                    '<div class="stage-card-footer"><span class="stage-chip muted">' + difficulty + '</span><span class="stage-action disabled">' + actionText + '</span></div>' +
                '</div>' +
            '</div>';
        } else {
            var stageDesc = isArcMode
                ? 'ARC baskını tek sabit kuralla çalışır; takım hazırsa operasyona çık.'
                : 'Harita brifingini incele, takımın hazırsa operasyonu başlat.';
            html += '<button class="' + cardClass + '" type="button" onclick="selectStage(' + i + ')" style="' + stageCardArt(s, i) + '" data-tip="' + esc(tipText) + '">' +
                '<div class="stage-card-inner">' +
                    '<div class="stage-card-top"><span class="stage-chip">&#128205; ' + (isArcMode ? 'ARC' : 'Harita') + '</span><span class="stage-chip">' + (isArcMode ? 'SABİT' : ('x' + s.multiplier)) + '</span></div>' +
                    '<div><div class="stage-card-title">' + esc(s.label) + '</div><div class="stage-card-desc">' + stageDesc + '</div></div>' +
                    '<div class="stage-card-footer"><span class="stage-chip muted">' + difficulty + '</span><span class="stage-action">' + actionText + '</span></div>' +
                '</div>' +
            '</button>';
        }
    }
    html += '</div>';

    setContent(html);
}

function selectStage(idx) {
    if ((screenData.selectedModeId || 'classic') === 'arc_pvp') {
        sendAction('startArcPvP', {});
        return;
    }

    sendAction('selectStage', {
        stageId: screenData.stages[idx].id,
        modeId: screenData.selectedModeId || 'classic'
    });
}

// ── Invite Players ─────────────────────────────────────────────────────────
function showInvite(data) {
    data = data || {};
    hideMainNavigation();
    currentScreen = 'invite';
    screenData.players = data.players || [];
    setBreadcrumb('Operasyon Menüsü / Davet');
    setHudState({
        health: 73,
        radiation: 24,
        inventoryPct: 48,
        inventoryText: '03/06',
        signal: 88,
        signalText: 'TARAMA',
        briefTitle: 'Yakındaki Oyuncular',
        briefText: 'Yakındaki oyuncuları seçerek takım daveti gönder.',
        briefTag: 'DAVET',
        progress: 63,
        slotsFilled: 3
    });

    var html = backBtn();
    html += '<div class="section-header"><div class="section-title">&#129309; Yakındaki Oyuncular</div></div>';

    if (screenData.players.length === 0) {
        html += emptyState('&#128123;', 'Davet edilebilecek oyuncu bulunamadı.');
        setContent(html);
        return;
    }

    for (var i = 0; i < screenData.players.length; i++) {
        var p = screenData.players[i];
        html += '<div class="player-item" data-tip="' + esc(p.name + ' (ID ' + p.id + '): takım daveti gönderebilirsin.') + '">' +
            '<div>' +
                '<div class="player-name">&#127918; ' + esc(p.name) + '</div>' +
                '<div class="player-id">ID: ' + p.id + ' · Yakında</div>' +
            '</div>' +
            '<button class="btn btn-primary" type="button" onclick="invitePlayer(' + i + ')">&#10133; Davet Et</button>' +
        '</div>';
    }

    setContent(html);
}

function invitePlayer(idx) {
    var p = screenData.players[idx];
    sendAction('invitePlayer', { playerId: p.id, name: p.name });
}

function showCreateLobbySetup() {
    hideMainNavigation();
    currentScreen = 'create-lobby';
    setBreadcrumb('Operasyon Menüsü / Lobi Görünürlüğü');
    setHudState({
        briefTitle: 'Lobi Görünürlüğü',
        briefText: 'Lobi türünü seç. Kurulum tamamlanınca ana ekrana dönersin.',
        briefTag: 'TAKIM',
        progress: 58,
        slotsFilled: 3
    });

    setContent(
        backBtn() +
        '<section class="lobby-setup-shell">' +
            '<div class="lobby-setup-hero">' +
                '<div class="lobby-setup-kicker">TAKIM KURULUMU</div>' +
                '<div class="lobby-setup-title">&#127968; Lobi Görünürlüğünü Seç</div>' +
                '<div class="lobby-setup-text">Herkese açık lobi listede görünür ve isteyen oyuncular doğrudan katılabilir. Özel lobi ise sadece senin davet ettiklerin için açıktır.</div>' +
                '<div class="lobby-setup-chips">' +
                    '<span class="lobby-setup-chip">&#128101; En fazla ' + esc(String(MAX_LOBBY_SIZE)) + ' oyuncu</span>' +
                    '<span class="lobby-setup-chip">&#9201; Seçimden sonra ana ekrana dönersin</span>' +
                '</div>' +
            '</div>' +
            '<div class="lobby-visibility-grid">' +
                '<button class="btn lobby-visibility-option is-public" type="button" onclick="createLobbyWithVisibility(true)">' +
                    '<span class="lobby-visibility-badge">Önerilen</span>' +
                    '<div class="lobby-visibility-icon">&#127758;</div>' +
                    '<strong>Herkese Açık</strong>' +
                    '<span>Aktif lobi listesinde görünür. Boş slot varsa oyuncular doğrudan takımına katılabilir.</span>' +
                    '<div class="lobby-visibility-points">' +
                        '<span>&#10003; Daha hızlı takım doldurma</span>' +
                        '<span>&#10003; Liste üzerinden katılım açık</span>' +
                        '<span>&#10003; Sonra yine oyuncu davet edebilirsin</span>' +
                    '</div>' +
                '</button>' +
                '<button class="btn lobby-visibility-option is-private" type="button" onclick="createLobbyWithVisibility(false)">' +
                    '<span class="lobby-visibility-badge">Kontrollü</span>' +
                    '<div class="lobby-visibility-icon">&#128274;</div>' +
                    '<strong>Özel</strong>' +
                    '<span>Lobi listesinde görünmez. Yalnızca senin gönderdiğin daveti kabul eden oyuncular katılabilir.</span>' +
                    '<div class="lobby-visibility-points">' +
                        '<span>&#10003; Tamamen davet tabanlı</span>' +
                        '<span>&#10003; Takımı kapalı tutar</span>' +
                        '<span>&#10003; Kontrollü grup kurulumuna uygun</span>' +
                    '</div>' +
                '</button>' +
            '</div>' +
        '</section>'
    );
}

function createLobbyWithVisibility(isPublic) {
    var optimisticState = Object.assign({}, screenData.menuState, {
        hasLobby: true,
        isLeader: true,
        isMember: false,
        isReady: false,
        lobbyStatus: (isPublic === true ? 'Herkese Açık' : 'Özel') + ' Lider'
    });
    screenData.menuState = optimisticState;
    showMenu(optimisticState);
    sendAction('createLobby', { isPublic: isPublic === true });
}

// ── Active Lobbies ───────────────────────────────────────────────────────────
function showActiveLobbies(data) {
    data = data || {};
    hideMainNavigation();
    currentScreen = 'active-lobbies';
    screenData.lobbies = data.lobbies || [];
    setBreadcrumb('Operasyon Menüsü / Aktif Lobiler');
    setHudState({
        health: 80,
        radiation: 22,
        inventoryPct: 60,
        inventoryText: describeCount(screenData.lobbies.length, 'lobi', 'lobi'),
        signal: 93,
        signalText: 'TAKIP',
        briefTitle: 'Açık Lobi İzleme',
        briefText: 'Sunucudaki aktif lobileri, liderlerini ve doluluk durumlarını takip et.',
        briefTag: 'LOBİLER',
        progress: 70,
        slotsFilled: clamp(screenData.lobbies.length, 1, 6)
    });

    var html = backBtn();
    html += '<div class="section-header"><div class="section-title">&#128101; Aktif Lobiler</div></div>';

    if (screenData.lobbies.length === 0) {
        html += emptyState('&#127968;', 'Şu anda görüntülenecek aktif lobi yok.');
        setContent(html);
        return;
    }

    for (var i = 0; i < screenData.lobbies.length; i++) {
        var lobby = screenData.lobbies[i];
        var maxPlayers = Number(lobby.maxPlayers || MAX_LOBBY_SIZE);
        var badge = lobby.isOwnLobby ? 'Senin Lobin' : (lobby.isJoinedLobby ? 'Bağlı Olduğun Lobi' : 'Açık Lobi');
        var badgeClass = lobby.isOwnLobby ? 'self' : (lobby.isJoinedLobby ? 'joined' : '');
        var visibilityText = lobby.isPublic ? 'Herkese Açık' : 'Özel';
        var joinAction = lobby.canJoin
            ? '<button class="btn btn-primary" type="button" onclick="joinPublicLobby(' + i + ')">&#10133; Lobiye Katıl</button>'
            : '';
        html += '<div class="card" data-tip="' + esc((lobby.leaderName || 'Bilinmeyen lider') + ': aktif lobi durumu ve doluluk özeti.') + '">' +
            '<div class="card-header">' +
                '<div class="card-title">' + esc(lobby.leaderName || 'Bilinmeyen Lider') + '</div>' +
                '<span class="menu-item-badge ' + badgeClass + '">' + esc(badge) + '</span>' +
            '</div>' +
            '<div class="card-desc">Lider ID: ' + esc(lobby.leaderId) + ' · Hazır oyuncular: ' + esc(lobby.readyCount) + '</div>' +
            screenMeter('Doluluk', clamp((Number(lobby.playerCount || 1) / maxPlayers) * 100, 12, 100)) +
            '<div class="req-chips">' +
                '<span class="req-chip"><span class="req-chip-amount">' + esc(visibilityText) + '</span>görünürlük</span>' +
                '<span class="req-chip"><span class="req-chip-amount">' + esc(lobby.playerCount) + '/' + esc(maxPlayers) + '</span>oyuncu</span>' +
                '<span class="req-chip"><span class="req-chip-amount">' + esc(lobby.memberCount) + '</span>üye</span>' +
                '<span class="req-chip"><span class="req-chip-amount">' + esc(lobby.readyCount) + '</span>hazır</span>' +
            '</div>' +
            (joinAction ? '<div class="card-footer">' + joinAction + '</div>' : '') +
        '</div>';
    }

    setContent(html);
}

// ── Lobby Members ──────────────────────────────────────────────────────────
function showMembers(data) {
    data = data || {};
    hideMainNavigation();
    currentScreen = 'members';
    screenData.members  = data.members  || [];
    screenData.memberLeaderId = data.leaderId;
    var leaderId = screenData.memberLeaderId;
    setBreadcrumb('Operasyon Menüsü / Takım');
    setHudState({
        health: 91,
        radiation: 26,
        inventoryPct: 66,
        inventoryText: describeCount(screenData.members.length, 'uye', 'uye'),
        signal: 92,
        signalText: 'FORMASYON',
        briefTitle: 'Takım Durumu',
        briefText: 'Takımdaki oyuncuları ve lider bilgisini buradan kontrol et.',
        briefTag: 'TAKIM',
        progress: 74,
        slotsFilled: clamp(screenData.members.length, 1, 6)
    });

    var html = backBtn();
    html += '<div class="section-header"><div class="section-title">&#128101; Takım Oyuncuları</div></div>';

    if (screenData.members.length === 0) {
        html += emptyState('&#127964;', 'Takımda görüntülenecek oyuncu kalmadı.');
        setContent(html);
        return;
    }

    for (var i = 0; i < screenData.members.length; i++) {
        var m = screenData.members[i];
        var leaderBadge = (m.id === leaderId) ? '<span class="leader-badge">Lider</span>' : '';
        var statusClass = m.isLeader ? 'leader' : (m.isReady ? 'ready' : 'waiting');
        var statusText = m.isLeader ? 'Lider' : (m.isReady ? 'Hazır' : 'Bekleniyor');
        html += '<div class="player-item" data-tip="' + esc(m.name + ': takım üyesi ' + (m.id === leaderId ? 've lider' : 'olarak listeleniyor') + '.') + '">' +
            '<div>' +
                '<div class="player-name">&#127894; ' + esc(m.name) + leaderBadge + '</div>' +
                '<div class="player-id">ID: ' + m.id + ' · <span class="member-status ' + statusClass + '">' + statusText + '</span></div>' +
            '</div>' +
        '</div>';
    }

    setContent(html);
}

// ── Receive Invite ─────────────────────────────────────────────────────────
function showReceiveInvite(data) {
    data = data || {};
    hideMainNavigation();
    currentScreen = 'invite-received';
    screenData.inviteLeaderId = data.leaderId;
    setBreadcrumb('Operasyon Menüsü / Gelen Davet');
    setHudState({
        health: 76,
        radiation: 31,
        inventoryPct: 54,
        inventoryText: '03/06',
        signal: 96,
        signalText: 'DAVET',
        briefTitle: 'Takım Daveti Alındı',
        briefText: 'Başka bir lider seni takımına çağırıyor. Daveti kabul edebilir veya reddedebilirsin.',
        briefTag: 'UYARI',
        progress: 88,
        slotsFilled: 3
    });

    setContent(
        '<div class="dialog-card" data-tip="Başka bir liderin takım daveti. Kabul ettiğinde o takıma katılırsın.">' +
            '<div class="dialog-icon">&#128233;</div>' +
            '<div class="dialog-title">Takım Daveti</div>' +
            '<div class="dialog-text">Bir takım lideri seni ekibine çağırıyor.<br>Katılmak istiyor musun?</div>' +
            '<div class="dialog-buttons">' +
                '<button class="btn btn-primary" type="button" onclick="acceptInvite()">&#9989; Katil</button>' +
                '<button class="btn btn-danger" type="button" onclick="denyInvite()">&#10060; Reddet</button>' +
            '</div>' +
        '</div>'
    );
}

function acceptInvite() {
    sendAction('acceptInvite', { leaderId: screenData.inviteLeaderId });
}

function joinPublicLobby(idx) {
    var lobby = screenData.lobbies[idx];
    if (!lobby) return;
    sendAction('joinPublicLobby', { leaderId: lobby.leaderId });
}

function denyInvite() {
    sendAction('denyInvite', {});
}

function showReconnectPrompt(data) {
    data = data || {};
    hideMainNavigation();
    currentScreen = 'arc-reconnect';
    screenData.reconnectPrompt = data;
    setBreadcrumb('ARC Bağlantı / Geri Katılım');
    setHudState({
        operatorCards: buildOperatorCards(),
        briefTitle: 'ARC Geri Katılım Onayı',
        briefText: 'Bağlantın koptu. Uygunsa aynı baskına son düştüğün noktadan geri dönebilirsin.',
        briefTag: 'UYARI',
        progress: 91,
        slotsFilled: 4
    });

    var extractionText = '';
    if (data.extraction && data.extraction.phaseLabel) {
        extractionText = '<div class="dialog-text"><strong>Son tahliye fazı:</strong> ' + esc(data.extraction.phaseLabel) + '</div>';
    }

    setContent(
        '<div class="dialog-card" data-tip="Evet dersen uygunluk hâlâ geçerliyse aynı ARC baskınına geri katılırsın. Hayır dersen güvenli dönüş uygulanır.">' +
            '<div class="dialog-icon">&#128257;</div>' +
            '<div class="dialog-title">' + esc(data.title || 'Oyuna geri katılmak ister misin?') + '</div>' +
            '<div class="dialog-text">' + esc(data.message || 'Bağlantın koptu. Aynı baskına geri katılmak ister misin?') + '</div>' +
            extractionText +
            '<div class="dialog-buttons">' +
                '<button class="btn btn-primary" type="button" onclick="submitArcReconnectDecision(true)">&#9989; Evet, Katıl</button>' +
                '<button class="btn btn-danger" type="button" onclick="submitArcReconnectDecision(false)">&#10060; Hayır</button>' +
            '</div>' +
        '</div>'
    );
}

function submitArcReconnectDecision(accepted) {
    sendAction('arcReconnectDecision', { accepted: accepted === true });
}
