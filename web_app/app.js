import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import {
  getAuth, onAuthStateChanged, signInWithEmailAndPassword, signOut
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";
import {
  getFirestore, collection, doc, getDoc, getDocs, onSnapshot, setDoc, serverTimestamp
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-firestore.js";
import { firebaseConfig } from "./firebase-config.js";
import { initWebEditor } from "./editor.js";

const $ = (id) => document.getElementById(id);
const TABLES = ["ingredients", "ingredient_prices", "recipes", "recipe_items", "recipe_prices", "settings"];
const LABELS = {
  ingredients: "Insumos",
  ingredient_prices: "Historial de precios de insumos",
  recipes: "Recetas",
  recipe_items: "Ingredientes de recetas",
  recipe_prices: "Historial de precios de recetas",
  settings: "Parámetros"
};
let app, auth, db, currentSnapshot = null, currentRecords = [];
let unsubscribeRecords = null;
let initError = "";

function setStatus(message, kind = "") {
  const el = $("status-message");
  el.textContent = message;
  el.className = "notice" + (kind ? " " + kind : "");
}
function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  }[c]));
}
function formatNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? new Intl.NumberFormat("es-AR", { maximumFractionDigits: 3 }).format(n) : "—";
}
function formatMoney(value) {
  const n = Number(value);
  return Number.isFinite(n) ? new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 2 }).format(n) : "—";
}
function dateText(value) {
  if (!value) return "—";
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? String(value) : new Intl.DateTimeFormat("es-AR").format(d);
}
function dateTimeText(value) {
  if (!value) return "—";
  const raw = typeof value.toDate === "function" ? value.toDate() : value;
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? "—" : new Intl.DateTimeFormat("es-AR",{dateStyle:"short",timeStyle:"short"}).format(d);
}
function emptyRow(cols, message) {
  return `<tr><td class="empty" colspan="${cols}">${escapeHtml(message)}</td></tr>`;
}
function tablesFromSnapshot() {
  return currentSnapshot && currentSnapshot.tables && typeof currentSnapshot.tables === "object"
    ? currentSnapshot.tables : null;
}

// Prefer the synchronized live records for any table that has been published by Android.
// Keep the manual snapshot only as a fallback for tables not yet present in records.
function tablesForDisplay() {
  const snapshotTables = tablesFromSnapshot() || {};
  const result = {};
  for (const table of TABLES) {
    const liveRows = new Map();
    let hasLiveRecords = false;
    for (const item of currentRecords) {
      const data = item.data || {};
      if (data.table !== table) continue;
      hasLiveRecords = true;
      const syncId = String(data.syncId || item.id);
      if (data.deleted === true) liveRows.delete(syncId);
      else liveRows.set(syncId, { ...(data.payload ?? {}), sync_id: syncId, _version: Number(data.version || 0) });
    }

    // Use one authoritative source per table. Merging snapshot rows with live records
    // can show the same ingredient or recipe twice when their IDs use different formats.
    if (hasLiveRecords) {
      result[table] = [...liveRows.values()];
      continue;
    }

    const snapshotRows = Array.isArray(snapshotTables[table]) ? snapshotTables[table] : [];
    const uniqueRows = new Map();
    for (const row of snapshotRows) {
      const key = row.sync_id ? String(row.sync_id) : (row.id != null ? `snapshot:${row.id}` : null);
      if (key) uniqueRows.set(key, row);
    }
    result[table] = [...uniqueRows.values()];
  }
  return result;
}
function buildSnapshotTables() {
  const live = new Map(TABLES.map(table => [table, new Map()]));
  for (const item of currentRecords) {
    const data = item.data || {};
    const table = data.table;
    const syncId = String(data.syncId || item.id || "");
    if (!live.has(table) || !syncId) continue;
    if (data.deleted === true) live.get(table).delete(syncId);
    else live.get(table).set(syncId, data.payload || {});
  }
  const rows = Object.fromEntries(TABLES.map(table => [table, []]));
  const ingredientIds = new Map();
  const recipeIds = new Map();

  const sorted = table => [...live.get(table).entries()].sort((a,b) => a[0].localeCompare(b[0]));
  sorted("ingredients").forEach(([syncId,p],index) => {
    const id = index + 1;
    ingredientIds.set(syncId,id);
    rows.ingredients.push({id,name:p.name ?? "",description:p.description ?? "",qty:p.qty ?? 0,unit:p.unit ?? "",price:p.price ?? 0,updated:p.updated ?? ""});
  });
  sorted("recipes").forEach(([syncId,p],index) => {
    const id = index + 1;
    recipeIds.set(syncId,id);
    rows.recipes.push({id,name:p.name ?? "",description:p.description ?? "",minutes:p.minutes ?? 0,yield_qty:p.yield_qty ?? 0,yield_unit:p.yield_unit ?? "",sale_qty:p.sale_qty ?? 0,sale_unit:p.sale_unit ?? "",portions_per_presentation:p.portions_per_presentation ?? 1,sale_price:p.sale_price ?? 0,updated:p.updated ?? "",sale_updated:p.sale_updated ?? ""});
  });
  sorted("ingredient_prices").forEach(([syncId,p],index) => {
    const parent = ingredientIds.get(String(p.ingredient_sync_id || ""));
    if (!parent) throw new Error("No se puede crear el respaldo: hay un historial de precios de insumo sin su insumo asociado.");
    rows.ingredient_prices.push({id:index+1,ingredient_id:parent,price:p.price ?? 0,date:p.date ?? ""});
  });
  sorted("recipe_prices").forEach(([syncId,p],index) => {
    const parent = recipeIds.get(String(p.recipe_sync_id || ""));
    if (!parent) throw new Error("No se puede crear el respaldo: hay un historial de precios de receta sin su receta asociada.");
    rows.recipe_prices.push({id:index+1,recipe_id:parent,price:p.price ?? 0,date:p.date ?? ""});
  });
  sorted("recipe_items").forEach(([syncId,p],index) => {
    const recipe = recipeIds.get(String(p.recipe_sync_id || ""));
    const ingredient = ingredientIds.get(String(p.ingredient_sync_id || ""));
    if (!recipe || !ingredient) throw new Error("No se puede crear el respaldo: hay un ingrediente de receta con referencias incompletas.");
    rows.recipe_items.push({id:index+1,recipe_id:recipe,ingredient_id:ingredient,qty:p.qty ?? 0,unit:p.unit ?? ""});
  });
  sorted("settings").forEach(([key,p]) => rows.settings.push({key,value:p.value ?? ""}));
  return rows;
}

async function updateManualSnapshot() {
  if (!auth.currentUser) return;
  const button = $("backup-button");
  button.disabled = true;
  button.textContent = "Generando copia…";
  try {
    if (!currentRecords.length) throw new Error("No hay registros individuales para respaldar. No se modificó la copia manual.");
    const tables = buildSnapshotTables();
    const uid = auth.currentUser.uid;
    const ref = doc(db,"users",uid,"appData","current");
    await setDoc(ref,{formatVersion:1,updatedAt:serverTimestamp(),tables});
    const saved = await getDoc(ref);
    currentSnapshot = saved.exists() ? saved.data() : null;
    renderAudit();
    renderIngredients();
    renderRecipes();
    setStatus("Copia manual actualizada correctamente a partir de los registros individuales vigentes. La sincronización automática no se modificó.","success");
  } catch (error) {
    console.error(error);
    setStatus(error?.message || "No se pudo actualizar la copia manual. No se modificaron los registros individuales.","warning");
  } finally {
    button.disabled = false;
    button.textContent = "Actualizar copia de respaldo";
  }
}

function renderAudit() {
  const snapshotTables = tablesFromSnapshot();
  const active = new Map(TABLES.map(t => [t, new Map()]));
  for (const item of currentRecords) {
    const data = item.data;
    const table = data.table;
    const syncId = data.syncId || item.id;
    if (!active.has(table) || !syncId) continue;
    const map = active.get(table);
    if (data.deleted === true) map.delete(syncId);
    else map.set(syncId, data.payload ?? {});
  }
  let html = '<table><thead><tr><th>Tabla</th><th>Copia manual</th><th>Registros activos</th><th>Estado</th></tr></thead><tbody>';
  for (const table of TABLES) {
    const snapCount = Array.isArray(snapshotTables?.[table]) ? snapshotTables[table].length : null;
    const recordsCount = active.get(table).size;
    let state = "Sin copia manual";
    if (snapCount !== null) {
      state = snapCount === recordsCount ? "Misma cantidad" : "Copia manual desactualizada";
      if (snapCount === 0 && recordsCount === 0) state = "Vacío en ambas";
    }
    const stateClass = state === "Misma cantidad" || state === "Vacío en ambas" ? "muted" : (state === "Copia manual desactualizada" ? "info-state" : "");
    html += `<tr><td>${escapeHtml(LABELS[table])}</td><td>${snapCount === null ? "—" : snapCount}</td><td>${recordsCount}</td><td class="${stateClass}">${escapeHtml(state)}</td></tr>`;
  }
  html += "</tbody></table>";
  $("audit-table-wrap").innerHTML = html;
  $("backup-updated-label").textContent = "Última copia manual: " + dateTimeText(currentSnapshot?.updatedAt);
  const recordsCount = currentRecords.filter(x => x.data.deleted !== true).length;
  $("count-records").textContent = formatNumber(recordsCount);
  const displayTables = tablesForDisplay();
  window.__appCostosRows = displayTables;
  $("count-ingredients").textContent = formatNumber(displayTables?.ingredients?.length ?? 0);
  $("count-recipes").textContent = formatNumber(displayTables?.recipes?.length ?? 0);

  if (!currentSnapshot) {
    setStatus("No se encontró la copia manual users/{uid}/appData/current. No se modificó ningún dato. Antes de seguir, verificá la sincronización manual desde Android.", "warning");
  } else {
    const mismatches = TABLES.filter(t => {
      const expected = Array.isArray(snapshotTables?.[t]) ? snapshotTables[t].length : null;
      return expected !== null && expected !== active.get(t).size;
    });
    if (mismatches.length) {
      setStatus("La copia manual es una referencia histórica y no se actualiza con cada cambio. En las tablas que tienen registros individuales, esos documentos son la fuente vigente que utiliza la web y Android. Las diferencias de cantidad con la copia manual son informativas y no indican por sí solas pérdida de datos.", "info");
    } else {
      setStatus("La copia manual y los registros individuales tienen la misma cantidad por tabla. Los cambios web se guardan como registros versionados compatibles con la sincronización de Android.", "");
    }
  }
}
function renderIngredients() {
  const rows = tablesForDisplay()?.ingredients;
  const filter = $("ingredient-filter").value.trim().toLocaleLowerCase("es-AR");
  if (!Array.isArray(rows)) {
    $("ingredients-body").innerHTML = emptyRow(4, "No hay datos de insumos en la copia manual.");
    return;
  }
  const filtered = rows.filter(r => String(r.name ?? "").toLocaleLowerCase("es-AR").includes(filter));
  $("ingredients-body").innerHTML = filtered.length ? filtered.map(r => `
    <tr><td><strong>${escapeHtml(r.name || "Sin nombre")}</strong>${r.description ? `<div class="muted">${escapeHtml(r.description)}</div>` : ""}</td>
    <td>${escapeHtml(formatNumber(r.qty))} ${escapeHtml(r.unit || "")}</td>
    <td>${escapeHtml(formatMoney(r.price))}</td><td>${escapeHtml(dateText(r.updated))}</td><td><button class="small secondary" data-edit="ingredient" data-sync-id="${escapeHtml(r.sync_id || "")}">Editar</button></td></tr>`).join("") : emptyRow(5, "No hay insumos que coincidan con la búsqueda.");
}
function renderRecipes() {
  const rows = tablesForDisplay()?.recipes;
  const filter = $("recipe-filter").value.trim().toLocaleLowerCase("es-AR");
  if (!Array.isArray(rows)) {
    $("recipes-body").innerHTML = emptyRow(4, "No hay datos de recetas en la copia manual.");
    return;
  }
  const filtered = rows.filter(r => String(r.name ?? "").toLocaleLowerCase("es-AR").includes(filter));
  $("recipes-body").innerHTML = filtered.length ? filtered.map(r => `
    <tr><td><strong>${escapeHtml(r.name || "Sin nombre")}</strong>${r.description ? `<div class="muted">${escapeHtml(r.description)}</div>` : ""}</td>
    <td>${escapeHtml(formatNumber(r.yield_qty))} ${escapeHtml(r.yield_unit || "")}</td>
    <td>${escapeHtml(formatMoney(r.sale_price))}</td><td>${escapeHtml(dateText(r.updated))}</td><td><button class="small secondary" data-edit="recipe" data-sync-id="${escapeHtml(r.sync_id || "")}">Editar</button></td></tr>`).join("") : emptyRow(5, "No hay recetas que coincidan con la búsqueda.");
}
async function loadData() {
  if (!auth.currentUser) return;
  setStatus("Consultando la copia manual y los registros individuales…");
  $("global-error").textContent = "";
  const uid = auth.currentUser.uid;
  try {
    const copyRef = doc(db, "users", uid, "appData", "current");
    const copySnap = await getDoc(copyRef);
    currentSnapshot = copySnap.exists() ? copySnap.data() : null;
    const recordsRef = collection(db, "users", uid, "records");
    const recordsSnap = await getDocs(recordsRef);
    currentRecords = recordsSnap.docs.map(d => ({ id: d.id, data: d.data() }));
    renderAudit();
    renderIngredients();
    renderRecipes();

    // Keep the web view synchronized while Android publishes record changes.
    if (unsubscribeRecords) unsubscribeRecords();
    unsubscribeRecords = onSnapshot(recordsRef, (snapshot) => {
      currentRecords = snapshot.docs.map(d => ({ id: d.id, data: d.data() }));
      renderAudit();
      renderIngredients();
      renderRecipes();
    }, (error) => {
      console.error(error);
      setStatus("No se pudo mantener la actualización en tiempo real. Podés usar el botón Actualizar para volver a consultar.", "warning");
    });
  } catch (error) {
    console.error(error);
    setStatus("No se pudieron leer los datos. Revisá la conexión, el proyecto Firebase y las reglas de Firestore.", "error-notice");
    $("global-error").textContent = error?.message || "Error al consultar Firebase.";
  }
}
$("login-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("login-error").textContent = "";
  if (initError) {
    $("login-error").textContent = initError;
    return;
  }
  try {
    await signInWithEmailAndPassword(auth, $("email").value.trim(), $("password").value);
  } catch (error) {
    $("login-error").textContent = error?.message || "No se pudo iniciar sesión.";
  }
});
$("logout-button").addEventListener("click", () => signOut(auth));
$("refresh-button").addEventListener("click", loadData);
$("backup-button").addEventListener("click", () => {
  if (window.confirm("Se reemplazará la copia manual actual por una fotografía completa de los registros individuales vigentes. Los registros de sincronización no se modificarán. ¿Querés continuar?")) updateManualSnapshot();
});
$("ingredient-filter").addEventListener("input", renderIngredients);
$("recipe-filter").addEventListener("input", renderRecipes);

if (firebaseConfig.apiKey.startsWith("REEMPLAZAR") || firebaseConfig.appId.startsWith("REEMPLAZAR")) {
  initError = "Falta configurar la aplicación web en web_app/firebase-config.js. Registrá una app Web en Firebase Console y pegá su configuración.";
  $("login-error").textContent = initError;
} else {
  try {
    app = initializeApp(firebaseConfig);
    auth = getAuth(app);
    db = getFirestore(app);
    onAuthStateChanged(auth, async user => {
      $("login-panel").hidden = !!user;
      $("app-panel").hidden = !user;
      if (user) {
        initWebEditor(auth, db);
        $("account-label").textContent = "Sesión iniciada: " + user.email;
        await loadData();
      } else {
        if (unsubscribeRecords) {
          unsubscribeRecords();
          unsubscribeRecords = null;
        }
        currentSnapshot = null;
        currentRecords = [];
      }
    });
  } catch (error) {
    initError = error?.message || "No se pudo iniciar Firebase.";
    $("login-error").textContent = initError;
  }
}
