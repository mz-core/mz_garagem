const STATE_LABELS = {
  stored: "Guardado",
  out: "Fora",
  impounded: "Impound",
  available: "Disponivel",
  active: "Ativo"
};

const CATEGORY_LABELS = {
  all: "Todos",
  car: "Carros",
  bike: "Motos",
  motorcycle: "Motos",
  suv: "SUV",
  sport: "Esportivos",
  sports: "Esportivos",
  super: "Super",
  compact: "Compactos",
  coupe: "Coupes",
  muscle: "Muscle",
  van: "Vans",
  offroad: "Off-road",
  service: "Servico",
  emergency: "Emergencia",
  sea: "Nauticos",
  air: "Aereos"
};

const KIND_LABELS = {
  owned: "Pessoal",
  org: "Organizacao",
  service: "Servico"
};

const UI_BUILD = "2026-04-21-render-debug-2";

const state = {
  open: false,
  garage: null,
  entries: [],
  selectedEntryId: null,
  search: "",
  selectedCategory: "all",
  ui: {
    title: "Garagem",
    allowNearbyStore: false,
    images: {
      baseUrl: "",
      extension: "webp",
      fallbackImage: "vehicle-fallback.svg"
    }
  }
};

const view = {
  visibleSignature: "",
  categorySignature: "",
  renderedCategory: "",
  lastLoggedSelectedEntryId: null
};

const els = {
  app: document.getElementById("app"),
  garageCount: document.getElementById("garage-count"),
  garageTitle: document.getElementById("garage-title"),
  categoryBar: document.getElementById("category-bar"),
  vehicleStage: document.getElementById("vehicle-stage"),
  vehicleSidecard: document.getElementById("vehicle-sidecard"),
  searchInput: document.getElementById("search-input"),
  closeBtn: document.getElementById("close-btn"),
  storeNearbyBtn: document.getElementById("store-nearby-btn")
};

console.info(`[mz_garagem/ui] build ${UI_BUILD} loaded`);
document.documentElement.dataset.mzGarageUiBuild = UI_BUILD;

function postNui(action, payload) {
  return fetch(`https://${GetParentResourceName()}/${action}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=UTF-8"
    },
    body: JSON.stringify(payload || {})
  }).catch(() => null);
}

function normalizeImagesConfig(images) {
  const next = images && typeof images === "object" ? images : {};
  return {
    baseUrl: String(next.baseUrl || ""),
    extension: String(next.extension || "webp").replace(/^\./, ""),
    fallbackImage: String(next.fallbackImage || "vehicle-fallback.svg")
  };
}

function normalizeUiPayload(data) {
  return {
    title: data && data.title ? String(data.title) : "Garagem",
    allowNearbyStore: data && data.allowNearbyStore === true,
    images: normalizeImagesConfig(data && data.images)
  };
}

function humanizeState(rawState) {
  const stateKey = String(rawState || "stored").toLowerCase();
  return STATE_LABELS[stateKey] || capitalize(stateKey);
}

function getStateTone(rawState) {
  const stateKey = String(rawState || "stored").toLowerCase();
  if (stateKey === "impounded") {
    return "warning";
  }

  if (stateKey === "out") {
    return "danger";
  }

  if (stateKey === "active") {
    return "info";
  }

  return "success";
}

function getCategoryLabel(category) {
  const key = String(category || "all").toLowerCase();
  return CATEGORY_LABELS[key] || capitalize(key);
}

function humanizeKind(rawKind) {
  const key = String(rawKind || "").toLowerCase();
  return KIND_LABELS[key] || "";
}

function getRenderableText(value, fallback = "") {
  const valueType = typeof value;
  if (valueType === "string" || valueType === "number" || valueType === "boolean") {
    const text = String(value).trim();
    if (text) {
      return text;
    }
  }

  const fallbackType = typeof fallback;
  if (fallbackType === "string" || fallbackType === "number" || fallbackType === "boolean") {
    return String(fallback).trim();
  }

  return "";
}

function isSuspiciousDisplayText(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return normalized.startsWith("table:") || normalized === "[object object]";
}

function debugValueType(value) {
  if (value === null) {
    return "null";
  }

  if (Array.isArray(value)) {
    return "array";
  }

  return typeof value;
}

function logRenderDebug(context, entry, resolvedName) {
  console.info(`[mz_garagem/ui][${UI_BUILD}][${context}]`, {
    entry_id: entry && entry.entry_id,
    vehicle_label: entry && entry.vehicle_label,
    vehicle_label_type: debugValueType(entry && entry.vehicle_label),
    vehicle_model: entry && entry.vehicle_model,
    vehicle_model_type: debugValueType(entry && entry.vehicle_model),
    resolved_name: resolvedName
  });
}

function getVehicleDisplayName(entry) {
  const model = getRenderableText(entry && entry.vehicle_model, "");
  const label = getRenderableText(entry && entry.vehicle_label, "");

  if (label && !isSuspiciousDisplayText(label)) {
    return label;
  }

  const resolvedName = model || "Vehicle";

  if (label || (entry && typeof entry.vehicle_label !== "undefined")) {
    console.warn(`[mz_garagem/ui][${UI_BUILD}][display-name-fallback] suspicious vehicle_label detected`, {
      entry_id: entry && entry.entry_id,
      vehicle_label: entry && entry.vehicle_label,
      vehicle_label_type: debugValueType(entry && entry.vehicle_label),
      vehicle_model: entry && entry.vehicle_model,
      resolved_name: resolvedName
    });
  }

  return resolvedName;
}

function getVehicleModelText(entry) {
  return getRenderableText(entry && entry.vehicle_model, "-");
}

function getVehiclePlateText(entry) {
  return getRenderableText(entry && entry.plate, "Sem placa");
}

function getBrandLabel(entry) {
  return getRenderableText(entry && entry.brand, "");
}

function capitalize(value) {
  const safe = String(value || "");
  return safe.charAt(0).toUpperCase() + safe.slice(1);
}

function escapeHtml(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function escapeAttr(value) {
  return escapeHtml(value);
}

function normalizeEntry(entry, index) {
  const vehicleLabel = getVehicleDisplayName(entry);
  const vehicleModel = getRenderableText(entry && entry.vehicle_model, "");
  const brand = getBrandLabel(entry);
  const plate = getRenderableText(entry && entry.plate, "");

  return {
    ...entry,
    _uid: `${entry.entry_id || "entry"}-${index}`,
    _searchText: [
      vehicleLabel,
      vehicleModel,
      brand,
      plate
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase()
  };
}

function getVisibleSignature(entries) {
  return entries.map((entry) => String(entry.entry_id || "")).join("|");
}

function getCategorySignature(entries) {
  return entries
    .map((entry) => String(entry.category || "all").toLowerCase())
    .sort()
    .join("|");
}

function getVisibleEntries() {
  const query = state.search.trim().toLowerCase();

  return state.entries.filter((entry) => {
    const matchesCategory =
      state.selectedCategory === "all" ||
      String(entry.category || "").toLowerCase() === state.selectedCategory;

    const matchesSearch = !query || entry._searchText.includes(query);

    return matchesCategory && matchesSearch;
  });
}

function getPrimaryAction(entry) {
  const actions = entry && entry.actions ? entry.actions : {};

  if (actions.release_impound) {
    return {
      action: "releaseImpound",
      label: "Liberar do impound",
      className: "warning",
      disabled: false
    };
  }

  if (actions.withdraw) {
    return {
      action: "withdraw",
      label: entry.kind === "service" ? "Retirar servico" : "Retirar veiculo",
      className: "",
      disabled: false
    };
  }

  if (String(entry.state || "") === "out") {
    return {
      action: "",
      label: "Veiculo fora da garagem",
      className: "",
      disabled: true
    };
  }

  return {
    action: "",
    label: "Sem acao disponivel",
    className: "",
    disabled: true
  };
}

function findDefaultEntry(entries) {
  if (!entries.length) {
    return null;
  }

  return entries.find((entry) => {
    const action = getPrimaryAction(entry);
    return action.disabled !== true;
  }) || entries[0];
}

function syncSelectedEntry(visibleEntries) {
  if (!visibleEntries.length) {
    state.selectedEntryId = null;
    return null;
  }

  const selected = visibleEntries.find((entry) => String(entry.entry_id) === String(state.selectedEntryId));
  if (selected) {
    return selected;
  }

  const fallback = findDefaultEntry(visibleEntries);
  state.selectedEntryId = fallback ? fallback.entry_id : null;
  return fallback;
}

function buildVehicleImageUrl(entry) {
  const images = state.ui.images || {};
  const fallback = images.fallbackImage || "vehicle-fallback.svg";
  const key = getRenderableText(entry && entry.image_key, getRenderableText(entry && entry.vehicle_model, ""));

  if (!key) {
    return fallback;
  }

  const baseUrl = String(images.baseUrl || "").trim();
  if (!baseUrl) {
    return fallback;
  }

  const extension = String(images.extension || "webp").replace(/^\./, "");
  const normalizedBaseUrl = baseUrl.endsWith("/") ? baseUrl : `${baseUrl}/`;
  return `${normalizedBaseUrl}${encodeURIComponent(key)}.${extension}`;
}

function getShortIdentifier(entry) {
  const rawPlate = getRenderableText(entry && entry.plate, "")
    .replace(/\s+/g, "")
    .trim()
    .toUpperCase();

  if (rawPlate) {
    return rawPlate.length > 8 ? rawPlate.slice(-8) : rawPlate;
  }

  const rawModel = getRenderableText(entry && entry.vehicle_model, "")
    .replace(/\s+/g, "")
    .trim()
    .toUpperCase();

  if (rawModel) {
    return rawModel.length > 8 ? rawModel.slice(0, 8) : rawModel;
  }

  return "SEM ID";
}

function wireImageFallbacks(root) {
  root.querySelectorAll("img[data-fallback]").forEach((image) => {
    image.addEventListener("error", () => {
      const fallback = image.dataset.fallback || "vehicle-fallback.svg";
      if (image.getAttribute("src") === fallback) {
        return;
      }

      image.setAttribute("src", fallback);
    });
  });
}

function syncThumbStripToSelection() {
  const thumbList = els.vehicleStage.querySelector(".thumb-list");
  if (!thumbList) {
    return;
  }

  if (thumbList.scrollWidth <= thumbList.clientWidth) {
    thumbList.scrollLeft = 0;
    return;
  }

  const selectedTile = Array.from(thumbList.querySelectorAll("[data-select-entry]")).find((button) => {
    return String(button.dataset.selectEntry || "") === String(state.selectedEntryId || "");
  });

  if (!selectedTile) {
    return;
  }

  const desiredLeft = selectedTile.offsetLeft - ((thumbList.clientWidth - selectedTile.offsetWidth) / 2);
  const maxScrollLeft = Math.max(0, thumbList.scrollWidth - thumbList.clientWidth);
  const nextScrollLeft = Math.max(0, Math.min(maxScrollLeft, desiredLeft));

  thumbList.scrollTo({
    left: nextScrollLeft,
    behavior: "smooth"
  });
}

function scalePercent(value, sourceMax) {
  const numeric = Number(value || 0);
  const max = Number(sourceMax || 100);

  if (max <= 0) {
    return 0;
  }

  if (numeric <= 100 && max === 100) {
    return Math.max(0, Math.min(100, Math.round(numeric)));
  }

  return Math.max(0, Math.min(100, Math.round((numeric / max) * 100)));
}

function renderCategories() {
  const categories = [{ id: "all", label: "Todos" }];
  const seen = new Set(["all"]);

  state.entries.forEach((entry) => {
    const category = String(entry.category || "all").toLowerCase();
    if (!seen.has(category)) {
      seen.add(category);
      categories.push({
        id: category,
        label: getCategoryLabel(category)
      });
    }
  });

  els.categoryBar.innerHTML = categories
    .map((category) => `
      <button
        type="button"
        class="category-chip ${state.selectedCategory === category.id ? "active" : ""}"
        data-category="${escapeAttr(category.id)}"
      >
        ${escapeHtml(category.label)}
      </button>
    `)
    .join("");

  els.categoryBar.querySelectorAll("[data-category]").forEach((button) => {
    button.addEventListener("click", () => {
      state.selectedCategory = button.dataset.category || "all";
      render();
    });
  });
}

function renderEmpty() {
  const emptyMarkup = `
    <div class="empty-shell">
      <div class="empty-state">
        <div class="empty-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.22.42-1.42 1.01L3 12v8h2v-2h14v2h2v-8l-2.08-5.99ZM6.85 7h10.29l1.04 3H5.81l1.04-3ZM19 16H5v-4h14v4Z"></path>
          </svg>
        </div>
        <h2 class="empty-title">Nenhum veiculo encontrado</h2>
        <p class="empty-text">
          Ajuste a busca, troque a categoria ou verifique se esta garagem possui veiculos elegiveis no momento.
        </p>
      </div>
    </div>
  `;

  els.vehicleStage.innerHTML = emptyMarkup;
  els.vehicleSidecard.innerHTML = emptyMarkup;
}

function buildThumbListMarkup(visibleEntries, selectedEntryId) {
  return visibleEntries.map((entry) => {
    const tone = getStateTone(entry.state);
    const displayName = getVehicleDisplayName(entry);
    if (isSuspiciousDisplayText(entry && entry.vehicle_label)) {
      logRenderDebug("thumb", entry, displayName);
    }
    return `
      <button
        type="button"
        class="thumb-card ${String(entry.entry_id) === String(selectedEntryId) ? "active" : ""}"
        data-select-entry="${escapeAttr(entry.entry_id)}"
      >
        <div class="thumb-card-image">
          <img
            src="${escapeAttr(buildVehicleImageUrl(entry))}"
            data-fallback="${escapeAttr(state.ui.images.fallbackImage || "vehicle-fallback.svg")}"
            alt="${escapeAttr(displayName)}"
          />
        </div>
        <div class="thumb-card-main">
          <div class="thumb-card-title">${escapeHtml(displayName)}</div>
          <div class="thumb-card-meta">
            <div class="thumb-card-plate">${escapeHtml(getShortIdentifier(entry))}</div>
            <span class="thumb-card-status ${escapeAttr(tone)}">${escapeHtml(humanizeState(entry.state))}</span>
          </div>
        </div>
      </button>
    `;
  }).join("");
}

function bindStageEvents() {
  const prevButton = els.vehicleStage.querySelector('[data-nav="prev"]');
  if (prevButton) {
    prevButton.addEventListener("click", () => {
      moveSelection(-1);
    });
  }

  const nextButton = els.vehicleStage.querySelector('[data-nav="next"]');
  if (nextButton) {
    nextButton.addEventListener("click", () => {
      moveSelection(1);
    });
  }

  els.vehicleStage.querySelectorAll("[data-select-entry]").forEach((button) => {
    button.addEventListener("click", () => {
      state.selectedEntryId = button.dataset.selectEntry;
      render();
    });
  });
}

function renderStageShell(visibleEntries, selectedEntry) {
  els.vehicleStage.innerHTML = `
    <div class="stage-top">
      <div class="stage-top-main">
        <span class="stage-kicker" data-stage-category></span>
        <p class="stage-brand" data-stage-brand></p>
        <h2 class="stage-name" data-stage-name></h2>
        <div class="stage-model" data-stage-model></div>
        <div class="stage-plate" data-stage-plate></div>
      </div>

      <span class="state-chip" data-stage-state></span>
    </div>

    <div class="stage-viewer">
      <button type="button" class="stage-nav-btn" data-nav="prev" aria-label="Anterior">
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="M15.41 7.41 14 6l-6 6 6 6 1.41-1.41L10.83 12z"></path>
        </svg>
      </button>

      <div class="stage-viewer-image">
        <img data-stage-image src="" alt="" data-fallback="${escapeAttr(state.ui.images.fallbackImage || "vehicle-fallback.svg")}" />
      </div>

      <button type="button" class="stage-nav-btn" data-nav="next" aria-label="Proximo">
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="m8.59 16.59 1.41 1.41 6-6-6-6-1.41 1.41L13.17 12z"></path>
        </svg>
      </button>
    </div>

    <div class="stage-footer">
      <div class="stage-counter" data-stage-counter></div>
      <div class="thumb-list">${buildThumbListMarkup(visibleEntries, selectedEntry.entry_id)}</div>
    </div>
  `;

  wireImageFallbacks(els.vehicleStage);
  bindStageEvents();
}

function updateThumbSelection() {
  els.vehicleStage.querySelectorAll("[data-select-entry]").forEach((button) => {
    const isActive = String(button.dataset.selectEntry || "") === String(state.selectedEntryId || "");
    button.classList.toggle("active", isActive);
  });
}

function updateStageSelection(visibleEntries, selectedEntry) {
  const selectedIndex = visibleEntries.findIndex((entry) => String(entry.entry_id) === String(selectedEntry.entry_id));
  const stateTone = getStateTone(selectedEntry.state);
  const stateLabel = humanizeState(selectedEntry.state);
  const stageImageUrl = buildVehicleImageUrl(selectedEntry);
  const stageDisplayName = getVehicleDisplayName(selectedEntry);
  const stageImageAlt = stageDisplayName;
  const brandLabel = getBrandLabel(selectedEntry);

  const stageCategory = els.vehicleStage.querySelector("[data-stage-category]");
  const stageBrand = els.vehicleStage.querySelector("[data-stage-brand]");
  const stageName = els.vehicleStage.querySelector("[data-stage-name]");
  const stageModel = els.vehicleStage.querySelector("[data-stage-model]");
  const stagePlate = els.vehicleStage.querySelector("[data-stage-plate]");
  const stageState = els.vehicleStage.querySelector("[data-stage-state]");
  const stageCounter = els.vehicleStage.querySelector("[data-stage-counter]");
  const stageImage = els.vehicleStage.querySelector("[data-stage-image]");

  if (view.lastLoggedSelectedEntryId !== String(selectedEntry.entry_id || "")) {
    logRenderDebug("stage", selectedEntry, stageDisplayName);
    view.lastLoggedSelectedEntryId = String(selectedEntry.entry_id || "");
  }

  if (stageCategory) {
    stageCategory.textContent = getCategoryLabel(selectedEntry.category);
  }

  if (stageBrand) {
    stageBrand.textContent = brandLabel;
    stageBrand.classList.toggle("is-hidden", !brandLabel);
  }

  if (stageName) {
    stageName.textContent = stageDisplayName;
  }

  if (stageModel) {
    stageModel.textContent = getVehicleModelText(selectedEntry);
  }

  if (stagePlate) {
    stagePlate.textContent = getVehiclePlateText(selectedEntry);
  }

  if (stageState) {
    stageState.className = `state-chip ${stateTone}`;
    stageState.textContent = stateLabel;
  }

  if (stageCounter) {
    stageCounter.textContent = `${selectedIndex + 1} / ${visibleEntries.length}`;
  }

  if (stageImage) {
    if (stageImage.getAttribute("src") !== stageImageUrl) {
      stageImage.setAttribute("src", stageImageUrl);
    }

    if (stageImage.getAttribute("alt") !== stageImageAlt) {
      stageImage.setAttribute("alt", stageImageAlt);
    }

    stageImage.dataset.fallback = state.ui.images.fallbackImage || "vehicle-fallback.svg";
  }

  updateThumbSelection();

  requestAnimationFrame(() => {
    syncThumbStripToSelection();
  });
}

function renderSidecard(selectedEntry) {
  const action = getPrimaryAction(selectedEntry);
  const fuelPercent = scalePercent(selectedEntry.fuel, 100);
  const enginePercent = scalePercent(selectedEntry.engine, 1000);
  const bodyPercent = scalePercent(selectedEntry.body, 1000);
  const storeNearbyHidden = state.ui.allowNearbyStore !== true ? "hidden" : "";

  els.vehicleSidecard.innerHTML = `
    <div class="sidecard-header">
      <div>
        <h3 class="sidecard-title">Detalhes do veiculo</h3>
        <p class="sidecard-subtitle">Selecione um veiculo para ver as informacoes e a acao principal disponivel.</p>
      </div>
    </div>

    <div class="stat-grid">
      <div class="stat-card">
        <div class="stat-label">Combustivel</div>
        <div class="stat-value">${fuelPercent}%</div>
        <div class="stat-bar"><div class="stat-bar-fill" style="width: ${fuelPercent}%"></div></div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Motor</div>
        <div class="stat-value">${enginePercent}%</div>
        <div class="stat-bar"><div class="stat-bar-fill" style="width: ${enginePercent}%"></div></div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Lataria</div>
        <div class="stat-value">${bodyPercent}%</div>
        <div class="stat-bar"><div class="stat-bar-fill" style="width: ${bodyPercent}%"></div></div>
      </div>
    </div>

    <div class="details-card">
      <div class="detail-row">
        <div class="detail-row-left">
          <div class="detail-row-icon">
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.22.42-1.42 1.01L3 12v8h2v-2h14v2h2v-8l-2.08-5.99ZM6.85 7h10.29l1.04 3H5.81l1.04-3ZM19 16H5v-4h14v4Z"></path>
            </svg>
          </div>
          <div>
            <div class="detail-row-label">Placa</div>
            <div class="detail-row-value">${escapeHtml(getVehiclePlateText(selectedEntry))}</div>
          </div>
        </div>
        <div class="detail-row-right">${escapeHtml(humanizeState(selectedEntry.state))}</div>
      </div>

      <div class="detail-row">
        <div class="detail-row-left">
          <div class="detail-row-icon">
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M12 2 6.5 11h4V22l5.5-9h-4L12 2Z"></path>
            </svg>
          </div>
          <div>
            <div class="detail-row-label">Modelo</div>
            <div class="detail-row-value">${escapeHtml(getVehicleModelText(selectedEntry))}</div>
          </div>
        </div>
        <div class="detail-row-right">${escapeHtml(getCategoryLabel(selectedEntry.category))}</div>
      </div>

      <div class="detail-row">
        <div class="detail-row-left">
          <div class="detail-row-icon">
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M12 4a8 8 0 1 0 8 8 8.01 8.01 0 0 0-8-8Zm0 14a6 6 0 1 1 6-6 6.01 6.01 0 0 1-6 6Zm1-10h-2v5l4.25 2.52 1.03-1.69L13 11.89Z"></path>
            </svg>
          </div>
          <div>
            <div class="detail-row-label">Local</div>
            <div class="detail-row-value">${escapeHtml(selectedEntry.location_label || "-")}</div>
          </div>
        </div>
        <div class="detail-row-right">${escapeHtml(humanizeKind(selectedEntry.kind) || "-")}</div>
      </div>
    </div>

    <div class="actions-wrap">
      <button
        type="button"
        class="primary-action-btn ${escapeAttr(action.className)}"
        data-action="${escapeAttr(action.action)}"
        data-entry-id="${escapeAttr(selectedEntry.entry_id)}"
        ${action.disabled ? "disabled" : ""}
      >
        ${escapeHtml(action.label)}
      </button>

      <button type="button" class="secondary-action-btn ${storeNearbyHidden}" id="side-store-nearby-btn">
        Guardar veiculo proximo
      </button>
    </div>

    <div class="hint-card">
      <h4 class="hint-title">Guardar proximo</h4>
      <p class="hint-text">
        Quando disponivel, essa acao tenta guardar um veiculo vazio, elegivel e proximo desta garagem sem exigir parar exatamente sobre o marcador.
      </p>
    </div>
  `;

  const primaryButton = els.vehicleSidecard.querySelector("[data-action]");
  if (primaryButton) {
    primaryButton.addEventListener("click", () => {
      const nextAction = primaryButton.dataset.action;
      const entryId = primaryButton.dataset.entryId;
      if (!nextAction || !entryId || primaryButton.disabled) {
        return;
      }

      postNui(nextAction, { entry_id: entryId });
    });
  }

  const nearbyButton = els.vehicleSidecard.querySelector("#side-store-nearby-btn");
  if (nearbyButton) {
    nearbyButton.addEventListener("click", () => {
      postNui("storeNearby", {});
    });
  }
}

function moveSelection(direction) {
  const visibleEntries = getVisibleEntries();
  if (!visibleEntries.length) {
    return;
  }

  const currentIndex = visibleEntries.findIndex((entry) => String(entry.entry_id) === String(state.selectedEntryId));
  const startIndex = currentIndex >= 0 ? currentIndex : 0;
  const nextIndex = (startIndex + direction + visibleEntries.length) % visibleEntries.length;
  state.selectedEntryId = visibleEntries[nextIndex].entry_id;
  render();
}

function render() {
  els.app.classList.toggle("visible", state.open);

  if (!state.open) {
    return;
  }

  const visibleEntries = getVisibleEntries();
  const selectedEntry = syncSelectedEntry(visibleEntries);
  const visibleSignature = getVisibleSignature(visibleEntries);
  const categorySignature = getCategorySignature(state.entries);

  const garageLabel = state.garage && state.garage.label ? state.garage.label : state.ui.title;
  els.garageTitle.textContent = garageLabel;
  els.garageCount.textContent = `${visibleEntries.length} veiculo${visibleEntries.length === 1 ? "" : "s"}`;
  els.storeNearbyBtn.classList.toggle("hidden", state.ui.allowNearbyStore !== true);

  if (view.categorySignature !== categorySignature || view.renderedCategory !== state.selectedCategory) {
    renderCategories();
    view.categorySignature = categorySignature;
    view.renderedCategory = state.selectedCategory;
  }

  if (!selectedEntry) {
    view.visibleSignature = "";
    renderEmpty();
    return;
  }

  if (view.visibleSignature !== visibleSignature) {
    renderStageShell(visibleEntries, selectedEntry);
    view.visibleSignature = visibleSignature;
  }

  updateStageSelection(visibleEntries, selectedEntry);
  renderSidecard(selectedEntry);
}

function openGarage(payload) {
  console.info(`[mz_garagem/ui][${UI_BUILD}] open payload received`, {
    garage_id: payload && payload.garage && payload.garage.id,
    entry_count: Array.isArray(payload && payload.entries) ? payload.entries.length : 0
  });

  state.open = true;
  state.garage = payload.garage || null;
  state.entries = (Array.isArray(payload.entries) ? payload.entries : []).map(normalizeEntry);
  state.ui = normalizeUiPayload(payload.ui);
  state.search = "";
  state.selectedCategory = "all";
  state.selectedEntryId = null;
  els.searchInput.value = "";

  const initialEntry = findDefaultEntry(state.entries);
  state.selectedEntryId = initialEntry ? initialEntry.entry_id : null;

  render();
}

function closeGarage() {
  state.open = false;
  state.garage = null;
  state.entries = [];
  state.selectedEntryId = null;
  state.search = "";
  state.selectedCategory = "all";
  view.visibleSignature = "";
  view.categorySignature = "";
  view.renderedCategory = "";
  view.lastLoggedSelectedEntryId = null;
  render();
}

window.addEventListener("message", (event) => {
  const data = event.data || {};

  if (data.action === "open") {
    openGarage(data);
  }

  if (data.action === "close") {
    closeGarage();
  }
});

window.addEventListener("keydown", (event) => {
  if (!state.open) {
    return;
  }

  if (event.key === "Escape") {
    postNui("close", {});
    return;
  }

  if (event.key === "ArrowLeft") {
    moveSelection(-1);
    return;
  }

  if (event.key === "ArrowRight") {
    moveSelection(1);
  }
});

els.searchInput.addEventListener("input", (event) => {
  state.search = String(event.target.value || "");
  render();
});

els.closeBtn.addEventListener("click", () => {
  postNui("close", {});
});

els.storeNearbyBtn.addEventListener("click", () => {
  postNui("storeNearby", {});
});
