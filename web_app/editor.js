import { doc, runTransaction } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-firestore.js";

let auth = null;
let db = null;
const $ = id => document.getElementById(id);
const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const uuid = () => crypto.randomUUID().replaceAll("-", "");
const number = value => {
  const s = String(value ?? "").trim().replace(/\s/g, "");
  if (s.includes(",") && s.includes(".")) return Number(s.lastIndexOf(",") > s.lastIndexOf(".") ? s.replace(/\./g, "").replace(",", ".") : s.replace(/,/g, ""));
  return Number(s.replace(",", "."));
};
const basePrice = (price, qty, unit) => qty > 0 ? price * (["g","gr","gramo","gramos","ml","cc","mililitro","mililitros"].includes(String(unit).toLowerCase()) ? 1000 : 1) / qty : 0;

function openEditor(kind, row) {
  const ingredient = kind === "ingredient";
  const fields = ingredient ? [
    ["name","Nombre",row?.name || "","text"],["description","Descripción",row?.description || "","text"],
    ["qty","Cantidad de presentación",row?.qty ?? "","number"],["unit","Unidad",row?.unit || "kg","unit"],
    ["price","Precio de presentación",row?.price ?? "","number"]
  ] : [
    ["name","Nombre",row?.name || "","text"],["description","Descripción",row?.description || "","text"],
    ["minutes","Tiempo de elaboración (min)",row?.minutes ?? 0,"number"],["yield_qty","Cantidad de rendimiento",row?.yield_qty ?? 1,"number"],
    ["yield_unit","Unidad de rendimiento",row?.yield_unit || "unidad","text"],["sale_qty","Cantidad por presentación de venta",row?.sale_qty ?? 1,"number"],
    ["sale_unit","Unidad de venta",row?.sale_unit || "unidad","text"],["portions_per_presentation","Porciones por presentación",row?.portions_per_presentation ?? 1,"number"],
    ["sale_price","Precio de venta",row?.sale_price ?? 0,"number"]
  ];
  $("editor-title").textContent = row ? (ingredient ? "Editar insumo" : "Editar receta") : (ingredient ? "Nuevo insumo" : "Nueva receta");
  $("editor-fields").innerHTML = fields.map(([name,label,value,type]) => {
    if (type === "unit") {
      const units = ["g","kg","l","ml","cc","unidad"];
      return '<label>'+esc(label)+'<select name="'+name+'" required>'+units.map(u=>'<option '+(u===value?"selected":"")+'>'+u+'</option>').join("")+'</select></label>';
    }
    return '<label>'+esc(label)+'<input name="'+name+'" type="'+type+'" value="'+esc(value)+'" '+(name==="name"?"required":"")+' '+(type==="number"?'min="0" step="any"':"")+'></label>';
  }).join("");
  $("editor-form").dataset.kind = kind;
  $("editor-form").dataset.syncId = row?.sync_id || "";
  $("editor-form").dataset.original = row ? JSON.stringify(row) : "";
  $("editor-error").textContent = "";
  $("editor-dialog").showModal();
}
async function save(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const kind = form.dataset.kind;
  const ingredient = kind === "ingredient";
  const original = form.dataset.original ? JSON.parse(form.dataset.original) : null;
  const values = Object.fromEntries(new FormData(form).entries());
  const numeric = ingredient ? ["qty","price"] : ["minutes","yield_qty","sale_qty","portions_per_presentation","sale_price"];
  for (const key of numeric) values[key] = number(values[key]);
  if (!values.name.trim() || numeric.some(k => !Number.isFinite(values[k]) || values[k] < 0) || (ingredient && values.qty <= 0)) {
    $("editor-error").textContent = "Completá el nombre y verificá que los valores numéricos sean válidos. La cantidad del envase debe ser mayor que cero.";
    return;
  }
  const table = ingredient ? "ingredients" : "recipes";
  const syncId = form.dataset.syncId || uuid();
  const now = new Date().toISOString();
  const displayed = window.__appCostosRows?.[table] || [];
  if (displayed.some(r => r.name?.trim().toLocaleLowerCase("es-AR") === values.name.trim().toLocaleLowerCase("es-AR") && r.sync_id !== syncId)) {
    $("editor-error").textContent = "Ya existe un registro con ese nombre.";
    return;
  }
  let payload, history = null;
  if (ingredient) {
    payload = {name:values.name.trim(),description:values.description.trim(),qty:values.qty,unit:values.unit,price:values.price,updated:now};
    const changed = !original || basePrice(Number(original.price),Number(original.qty),original.unit) !== basePrice(values.price,values.qty,values.unit);
    if (changed) history = {table:"ingredient_prices",syncId:uuid(),payload:{ingredient_sync_id:syncId,price:basePrice(values.price,values.qty,values.unit),date:now}};
  } else {
    payload = {name:values.name.trim(),description:values.description.trim(),minutes:values.minutes,yield_qty:values.yield_qty,yield_unit:values.yield_unit.trim(),sale_qty:values.sale_qty,sale_unit:values.sale_unit.trim(),portions_per_presentation:values.portions_per_presentation,sale_price:values.sale_price,updated:now,sale_updated:original?.sale_updated || now};
    if (!original || Number(original.sale_price) !== values.sale_price) {
      payload.sale_updated = now;
      history = {table:"recipe_prices",syncId:uuid(),payload:{recipe_sync_id:syncId,price:values.sale_price,date:now}};
    }
  }
  try {
    const uid = auth.currentUser.uid;
    const mainRef = doc(db,"users",uid,"records",table+"__"+syncId);
    const historyRef = history ? doc(db,"users",uid,"records",history.table+"__"+history.syncId) : null;
    await runTransaction(db, async tx => {
      const current = await tx.get(mainRef);
      const version = current.exists() ? Number(current.data().version || 0) : 0;
      if (original && version !== Number(original._version || 0)) throw new Error("Este registro cambió desde que lo abriste. Cerrá el formulario, actualizá los datos y volvé a editarlo.");
      tx.set(mainRef,{table,syncId,version:version+1,deleted:false,payload,updatedAt:new Date()});
      if (historyRef) tx.set(historyRef,{table:history.table,syncId:history.syncId,version:1,deleted:false,payload:history.payload,updatedAt:new Date()});
    });
    $("editor-dialog").close();
    $("status-message").textContent = "Cambios guardados en Firestore. Android los recibirá en su próxima sincronización.";
    $("status-message").className = "notice success";
  } catch (error) {
    console.error(error);
    $("editor-error").textContent = error?.message || "No se pudo guardar el cambio.";
  }
}
export function initWebEditor(firebaseAuth, firestore) {
  auth = firebaseAuth;
  db = firestore;
  if ($("editor-dialog").dataset.initialized) return;
  $("editor-dialog").dataset.initialized = "1";
  $("new-ingredient-button").addEventListener("click",()=>openEditor("ingredient",null));
  $("new-recipe-button").addEventListener("click",()=>openEditor("recipe",null));
  $("editor-form").addEventListener("submit",save);
  $("editor-cancel").addEventListener("click",()=>$("editor-dialog").close());
  document.addEventListener("click",event=>{
    const button=event.target.closest("[data-edit]");
    if (!button) return;
    const kind=button.dataset.edit;
    const table=kind==="ingredient"?"ingredients":"recipes";
    const row=(window.__appCostosRows?.[table] || []).find(r=>r.sync_id===button.dataset.syncId);
    if(row) openEditor(kind,row);
  });
}
