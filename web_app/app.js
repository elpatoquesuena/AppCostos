import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import {
  getAuth, onAuthStateChanged, signInWithEmailAndPassword, signOut
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";
import {
  getFirestore, collection, doc, getDoc, getDocs, onSnapshot
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-firestore.js";
import { firebaseConfig } from "./firebase-config.js";

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
  const liveByTable = new Map(TABLES.map(table => [table, new Map()]));
  const seenTables = new Set();
  for (const item of currentRecords) {
    const data = item.data || {};
    const table = data.table;
    const syncId = data.syncId || item.id;
    if (!liveByTable.has(table) || !syncId) continue;
    seenTables.add(table);
    const rows = liveByTable.get(table);
    if (data.deleted === true) rows.delete(syncId);
    else rows.set(syncId, data.payload ?? {});
  }
  const result = { ...snapshotTables };
  for (const table of seenTables) result[table] = [...liveByTable.get(table).values()];
  return result;
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
      state = snapCount === recordsCount ? "Misma cantidad" : "Revisar diferencia";
      if (snapCount === 0 && recordsCount === 0) state = "Vacío en ambas";
    }
    const stateClass = state === "Misma cantidad" || state === "Vacío en ambas" ? "muted" : "";
    html += `<tr><td>${escapeHtml(LABELS[table])}</td><td>${snapCount === null ? "—" : snapCount}</td><td>${recordsCount}</td><td class="${stateClass}">${escapeHtml(state)}</td></tr>`;
  }
  html += "</tbody></table>";
  $("audit-table-wrap").innerHTML = html;
  const recordsCount = currentRecords.filter(x => x.data.deleted !== true).length;
  $("count-records").textContent = formatNumber(recordsCount);
  const displayTables = tablesForDisplay();
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
      setStatus("La copia manual existe, pero hay diferencias de cantidad en una o más tablas. Esta fase usa solo la copia manual para mostrar datos; no habilita escrituras. Hay que revisar la sincronización antes de elegir una fuente compartida.", "warning");
    } else {
      setStatus("La copia manual y los registros individuales tienen la misma cantidad por tabla. Esto es una comprobación inicial; todavía falta comparar el contenido y las relaciones antes de habilitar escrituras.", "");
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
    <td>${escapeHtml(formatMoney(r.price))}</td><td>${escapeHtml(dateText(r.updated))}</td></tr>`).join("") : emptyRow(4, "No hay insumos que coincidan con la búsqueda.");
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
    <td>${escapeHtml(formatMoney(r.sale_price))}</td><td>${escapeHtml(dateText(r.updated))}</td></tr>`).join("") : emptyRow(4, "No hay recetas que coincidan con la búsqueda.");
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
