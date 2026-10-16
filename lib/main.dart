import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.open();
  await seedSamples();
  runApp(const CostosApp());
}

Future<void> seedSamples() async {
  final db=Store.instance.db;
  final samples=<Map<String,Object>>[
    {'name':'Manteca','description':'','qty':2.5,'unit':'kg','price':25000},
    {'name':'Sal','description':'','qty':500,'unit':'g','price':1785},
    {'name':'Harina 0000','description':'','qty':1,'unit':'kg','price':1190},
    {'name':'Polvo de hornear','description':'','qty':1,'unit':'kg','price':7285},
    {'name':'Queso para rallar','description':'','qty':100,'unit':'g','price':2900},
    {'name':'Leche','description':'','qty':1,'unit':'l','price':2100},
    {'name':'Crema','description':'','qty':1,'unit':'kg','price':7800},
  ];
  final ids=<String,int>{};
  for(final s in samples){
    final existing=await db.query('ingredients',where:'LOWER(name)=?',whereArgs:[(s['name'] as String).toLowerCase()],limit:1);
    int id;
    if(existing.isNotEmpty){id=existing.first['id'] as int;}
    else {
      final now=stamp();
      id=await db.insert('ingredients',{...s,'updated':now});
      await db.insert('ingredient_prices',{'ingredient_id':id,'price':s['price'],'date':now});
    }
    ids[s['name'] as String]=id;
  }
  final found=await db.query('recipes',where:'LOWER(name)=?',whereArgs:['scon de queso'],limit:1);
  if(found.isNotEmpty)return;
  final now=stamp();
  final rid=await db.insert('recipes',{'name':'Scon de queso','description':'Scon de queso reggianito.','minutes':15,'yield_qty':8,'yield_unit':'unidad','sale_qty':1,'sale_unit':'unidad','sale_price':4000,'updated':now,'sale_updated':now});
  await db.insert('recipe_prices',{'recipe_id':rid,'price':4000,'date':now});
  const used=<String,double>{'Manteca':200,'Sal':10,'Harina 0000':440,'Polvo de hornear':10,'Queso para rallar':200,'Leche':100,'Crema':100};
  for(final e in used.entries){
    await db.insert('recipe_items',{'recipe_id':rid,'ingredient_id':ids[e.key],'qty':e.value,'unit':e.key=='Leche'?'ml':'g'});
  }
}

class Store {
  Store._();
  static final Store instance = Store._();
  late Database db;
  Future<void> open() async {
    db = await openDatabase(path.join(await getDatabasesPath(), 'app_costos.db'),
      version: 2,
      onUpgrade: (d, oldVersion, newVersion) async { if(oldVersion<2) await d.execute('CREATE TABLE IF NOT EXISTS recipe_prices(id INTEGER PRIMARY KEY AUTOINCREMENT,recipe_id INTEGER NOT NULL,price REAL NOT NULL,date TEXT NOT NULL)'); },
      onCreate: (d, v) async {
        await d.execute('CREATE TABLE ingredients(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,description TEXT NOT NULL DEFAULT "",qty REAL NOT NULL,unit TEXT NOT NULL,price REAL NOT NULL,updated TEXT NOT NULL)');
        await d.execute('CREATE TABLE ingredient_prices(id INTEGER PRIMARY KEY AUTOINCREMENT,ingredient_id INTEGER NOT NULL,price REAL NOT NULL,date TEXT NOT NULL)');
        await d.execute('CREATE TABLE recipes(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,description TEXT NOT NULL DEFAULT "",minutes REAL NOT NULL DEFAULT 0,yield_qty REAL NOT NULL DEFAULT 1,yield_unit TEXT NOT NULL DEFAULT "unidad",sale_qty REAL NOT NULL DEFAULT 1,sale_unit TEXT NOT NULL DEFAULT "unidad",sale_price REAL NOT NULL DEFAULT 0,updated TEXT NOT NULL,sale_updated TEXT NOT NULL)');
        await d.execute('CREATE TABLE recipe_items(id INTEGER PRIMARY KEY AUTOINCREMENT,recipe_id INTEGER NOT NULL,ingredient_id INTEGER NOT NULL,qty REAL NOT NULL,unit TEXT NOT NULL)');
        await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)');
        await d.insert('settings', {'key':'hourly_rate','value':'0'});
        await d.insert('settings', {'key':'ideal_margin','value':'60'});
        await d.execute('CREATE TABLE recipe_prices(id INTEGER PRIMARY KEY AUTOINCREMENT,recipe_id INTEGER NOT NULL,price REAL NOT NULL,date TEXT NOT NULL)');
      });
  }
}

String fmt(num n) {
  final s=n.toStringAsFixed(n % 1 == 0 ? 0 : 2);
  final p=s.split('.'); final w=p[0]; final b=StringBuffer();
  for(var i=0;i<w.length;i++){if(i>0&&(w.length-i)%3==0)b.write('.');b.write(w[i]);}
  return p.length>1?'${b.toString()},${p[1]}':b.toString();
}
String cash(num n) => r'$' + fmt(n);
String titleCase(String s) { final v=s.trim(); return v.isEmpty?v:v[0].toUpperCase()+v.substring(1); }
String stamp() => DateTime.now().toIso8601String();
String dateLabel(String value) {
  final d=DateTime.tryParse(value); if(d==null)return value;
  return d.day.toString().padLeft(2,'0')+'/'+d.month.toString().padLeft(2,'0')+'/'+d.year.toString();
}
double number(String? s) {
  var v=(s??'').trim().replaceAll(' ','');
  if(v.contains(',')&&v.contains('.')) { if(v.lastIndexOf(',')>v.lastIndexOf('.'))v=v.replaceAll('.','').replaceAll(',','.');else v=v.replaceAll(',',''); }
  else if(v.contains(',')) v=v.replaceAll('.','').replaceAll(',','.');
  else if(RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(v)) v=v.replaceAll('.','');
  return double.tryParse(v)??0;
}
class CostosApp extends StatelessWidget {
  const CostosApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Calculadora de costos', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF356859)), scaffoldBackgroundColor: const Color(0xFFF7F8F5)),
    home: const MainPage(),
  );
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override State<MainPage> createState() => _MainPageState();
}
class _MainPageState extends State<MainPage> {
  int index = 0;
  int revision = 0;
  void refresh() => setState(() => revision++);
  @override Widget build(BuildContext context) {
    final pages = [
      Dashboard(key: ValueKey('home'+revision.toString()), go: (i) => setState(() => index=i)),
      IngredientsPage(key: ValueKey('ingredients'+revision.toString()), onChange: refresh),
      RecipesPage(key: ValueKey('recipes'+revision.toString()), onChange: refresh),
      SettingsPage(key: ValueKey('settings'+revision.toString())),
    ];
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && index != 0 && mounted) {
          setState(() => index = 0);
        }
      },
      child: SafeArea(child: Scaffold(
      appBar: index==0 ? null : AppBar(title: Text(const ['Inicio','Insumos','Recetas','Parámetros'][index])),
      body: IndexedStack(index:index, children:pages),
      bottomNavigationBar: NavigationBar(selectedIndex:index,onDestinationSelected:(i)=>setState(()=>index=i),destinations:const [
        NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'Inicio'),
        NavigationDestination(icon:Icon(Icons.inventory_2_outlined),label:'Insumos'),
        NavigationDestination(icon:Icon(Icons.menu_book_outlined),label:'Recetas'),
        NavigationDestination(icon:Icon(Icons.tune),label:'Parámetros'),
      ]),
      )),
    );
  }
}

class Dashboard extends StatelessWidget {
  final ValueChanged<int> go;
  const Dashboard({super.key, required this.go});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Costeá mejor. Decidí con datos.',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('Controlá los precios de tus insumos y calculá el costo de tus recetas.'),
        const SizedBox(height: 20),
        FutureBuilder<List<int>>(
          future: Future.wait([
            Store.instance.db.rawQuery('SELECT COUNT(*) c FROM ingredients')
                .then((r) => r.first['c'] as int),
            Store.instance.db.rawQuery('SELECT COUNT(*) c FROM recipes')
                .then((r) => r.first['c'] as int),
          ]),
          builder: (context, snapshot) {
            final counts = snapshot.data;
            return Column(
              children: [
                Card(
                  child: InkWell(
                    onTap: () => go(1),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 36),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  counts == null ? '…' : counts[0].toString(),
                                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                                ),
                                const Text('Insumos registrados'),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward),
                        ],
                      ),
                    ),
                  ),
                ),
                Card(
                  child: InkWell(
                    onTap: () => go(2),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          const Icon(Icons.menu_book_outlined, size: 36),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  counts == null ? '…' : counts[1].toString(),
                                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                                ),
                                const Text('Recetas registradas'),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Actualizá el precio de los insumos cada vez que comprás para mantener los costos al día.'),
          ),
        ),
      ],
    );
  }
}

Future<void> editDialog(BuildContext context, String title, List<FormFieldSpec> fields, Future<void> Function(Map<String,String>) onSave) async {
  final controllers = <String,TextEditingController>{for(final f in fields) f.key:TextEditingController(text:f.initial)};
  final key = GlobalKey<FormState>();
  await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
    title:Text(title),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: fields.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: f.options != null ? DropdownButtonFormField<String>(value:f.options!.contains(controllers[f.key]!.text)?controllers[f.key]!.text:null,decoration:InputDecoration(labelText:f.label),items:f.options!.map((o)=>DropdownMenuItem(value:o,child:Text(o))).toList(),onChanged:(v){if(v!=null)controllers[f.key]!.text=v;},validator:f.required?(v)=>(v==null||v.isEmpty)?'Campo obligatorio':null:null) : TextFormField(
                controller: controllers[f.key],
                keyboardType: f.numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                decoration: InputDecoration(labelText: f.label),
                validator: f.required ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : (f.numeric && number(v)<=0 && f.key!='minutes' ? 'Ingresá un valor mayor que cero' : null) : null,
              ),
            )).toList(),
          ),
        ),
      ),
    ),
    actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),FilledButton(onPressed:()async{if(!key.currentState!.validate())return;final values={for(final e in controllers.entries)e.key:e.value.text.trim()};Navigator.pop(ctx);await onSave(values);},child:const Text('Guardar'))],
  ));
  for(final c in controllers.values){c.dispose();}
}
class FormFieldSpec {
  final String key,label,initial; final bool numeric,required; final List<String>? options;
  const FormFieldSpec(this.key,this.label,{this.initial='',this.numeric=false,this.required=true,this.options});
}

class IngredientsPage extends StatefulWidget {
  final VoidCallback onChange;
  const IngredientsPage({super.key,required this.onChange});
  @override State<IngredientsPage> createState()=>_IngredientsPageState();
}
class _IngredientsPageState extends State<IngredientsPage> {
  String query='';
  final searchController=TextEditingController();
  Future<List<Map<String,Object?>>> get data=>Store.instance.db.query('ingredients',orderBy:'name COLLATE NOCASE');
  Future<void> add() async {
    await editDialog(context,'Nuevo insumo',[
      FormFieldSpec('name','Nombre',initial:query.trim()),const FormFieldSpec('description','Descripción',required:false),
      const FormFieldSpec('qty','Cantidad de la presentación',numeric:true),const FormFieldSpec('unit','Unidad',options:['g','kg','l','ml','cc','unidad']),const FormFieldSpec('price','Precio actual',numeric:true),
    ],(v)async{
      final normalized=titleCase(v['name']??'');
      final dup=await Store.instance.db.query('ingredients',where:'LOWER(name)=?',whereArgs:[normalized.toLowerCase()],limit:1);
      if(dup.isNotEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ya existe un insumo con ese nombre.')));return;}
      final now=stamp();final price=number(v['price']);
      final id=await Store.instance.db.insert('ingredients',{'name':normalized,'description':v['description']??'','qty':number(v['qty']),'unit':v['unit'],'price':price,'updated':now});
      await Store.instance.db.insert('ingredient_prices',{'ingredient_id':id,'price':price,'date':now});
      if(mounted)setState((){});widget.onChange();
    });
  }
  Future<void> editIngredient(Map<String,Object?> item) async {
    await editDialog(context,'Editar insumo',[
      FormFieldSpec('name','Nombre',initial:item['name'] as String),
      FormFieldSpec('description','Descripción',initial:item['description'] as String,required:false),
      FormFieldSpec('qty','Cantidad de la presentación',initial:item['qty'].toString(),numeric:true),
      FormFieldSpec('unit','Unidad',initial:item['unit'] as String,options:['g','kg','l','ml','cc','unidad']),
      FormFieldSpec('price','Precio actual',initial:item['price'].toString(),numeric:true),
    ],(v)async{
      final normalized=titleCase(v['name']??'');
      final dup=await Store.instance.db.query('ingredients',where:'LOWER(name)=? AND id<>?',whereArgs:[normalized.toLowerCase(),item['id']],limit:1);
      if(dup.isNotEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ya existe un insumo con ese nombre.')));return;}
      final now=stamp();
      final price=number(v['price']);
      final oldPrice=(item['price'] as num).toDouble();
      final qty=number(v['qty']);
      if(qty<=0){
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('La cantidad de la presentación debe ser mayor que cero.')));
        return;
      }
      await Store.instance.db.update('ingredients',{
        'name':normalized,
        'description':v['description']??'',
        'qty':qty,
        'unit':v['unit'],
        'price':price,
        'updated':now,
      },where:'id=?',whereArgs:[item['id']]);
      // Registrar un nuevo punto del historial solo cuando cambie el precio.
      if(price!=oldPrice){
        await Store.instance.db.insert('ingredient_prices',{'ingredient_id':item['id'],'price':price,'date':now});
      }
      if(mounted)setState((){});
      widget.onChange();
    });
  }
  Future<void> priceUpdate(Map<String,Object?> item) async {
    await editDialog(context,'Actualizar precio',const [FormFieldSpec('price','Nuevo precio',numeric:true)],(v)async{
      final price=number(v['price']);final now=stamp();
      await Store.instance.db.update('ingredients',{'price':price,'updated':now},where:'id=?',whereArgs:[item['id']]);
      await Store.instance.db.insert('ingredient_prices',{'ingredient_id':item['id'],'price':price,'date':now});
      if(mounted)setState((){});widget.onChange();
    });
  }
  Future<void> detail(Map<String,Object?> item) async {
    final history=await Store.instance.db.query('ingredient_prices',where:'ingredient_id=?',whereArgs:[item['id']],orderBy:'date DESC');
    final recipes=await Store.instance.db.rawQuery('SELECT recipes.name FROM recipes JOIN recipe_items ON recipes.id=recipe_items.recipe_id WHERE recipe_items.ingredient_id=?',[item['id']]);
    if(!mounted)return;
    showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text(item['name'] as String),content:SizedBox(width:400,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text((item['description'] as String).isEmpty?'Sin descripción':item['description'] as String),
      const SizedBox(height:8),Text('Presentación: ${fmt(item['qty'] as num)} ${item['unit']}'),
      Text('Precio actual de la presentación: '+cash(item['price'] as num)),
      Text('Precio por unidad base: '+cash((item['price'] as num)/((item['qty'] as num).toDouble()<=0?1:(item['qty'] as num).toDouble())*(['kg','l'].contains(item['unit'])?1:['g','ml','cc'].contains(item['unit'])?1000:1))),
      Text('Última actualización: '+dateLabel(item['updated'] as String)),
      const Divider(),const Text('Historial de precios',style:TextStyle(fontWeight:FontWeight.bold)),
      ...history.map((h)=>ListTile(contentPadding:EdgeInsets.zero,title:Text(cash(h['price'] as num)),subtitle:Text(dateLabel(h['date'] as String)))),
      const Divider(),const Text('Recetas que lo usan',style:TextStyle(fontWeight:FontWeight.bold)),
      if(recipes.isEmpty)const Text('Ninguna por ahora.'),...recipes.map((r)=>Text('• '+(r['name'] as String))),
    ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),FilledButton.icon(onPressed:(){Navigator.pop(ctx);editIngredient(item);},icon:const Icon(Icons.edit),label:const Text('Actualizar información'))]));
  }
  Future<void> remove(Map<String,Object?> item) async {
    final used=await Store.instance.db.query('recipe_items',where:'ingredient_id=?',whereArgs:[item['id']],limit:1);
    if(used.isNotEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No se puede eliminar: está asociado a una receta.')));return;}
    if(!mounted)return;
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Eliminar insumo'),content:Text('¿Eliminar '+(item['name'] as String)+'?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Eliminar'))]));
    if(yes==true){await Store.instance.db.delete('ingredient_prices',where:'ingredient_id=?',whereArgs:[item['id']]);await Store.instance.db.delete('ingredients',where:'id=?',whereArgs:[item['id']]);if(mounted)setState((){});widget.onChange();}
  }
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:TextField(controller:searchController,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar o registrar insumo',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>query=v))),
    Expanded(child:FutureBuilder<List<Map<String,Object?>>>(future:data,builder:(c,s){
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final list=s.data!.where((x)=>(x['name'] as String).toLowerCase().contains(query.toLowerCase())).toList();
      final exact=list.any((x)=>(x['name'] as String).toLowerCase()==query.trim().toLowerCase());
      final canCreate=query.trim().isNotEmpty&&!exact;
      if(list.isEmpty&&!canCreate)return const Center(child:Text('Buscá un insumo por su nombre.'));
      return ListView(children:[if(canCreate)Card(child:ListTile(leading:const Icon(Icons.add_circle_outline),title:Text('Registrar ${titleCase(query)}'),subtitle:const Text('Crear un insumo nuevo'),onTap:add)),...list.map((x)=>Card(child:ListTile(title:Text(x['name'] as String),subtitle:Text('${fmt(x['qty'] as num)} ${x['unit']} · ${dateLabel(x['updated'] as String)}'),trailing:Text(cash(x['price'] as num),style:const TextStyle(fontWeight:FontWeight.bold)),onTap:()=>detail(x),onLongPress:()=>remove(x))))]);
    })),
  ]);
  @override void dispose(){searchController.dispose();super.dispose();}
}

class RecipesPage extends StatefulWidget {
  final VoidCallback onChange;
  const RecipesPage({super.key,required this.onChange});
  @override State<RecipesPage> createState()=>_RecipesPageState();
}
class _RecipesPageState extends State<RecipesPage> {
  String query=''; final searchController=TextEditingController();
  Future<List<Map<String,Object?>>> get data=>Store.instance.db.query('recipes',orderBy:'name COLLATE NOCASE');
  // Normaliza unidades a una unidad base: g, ml o unidad.
  // Así, por ejemplo, 100 ml de una presentación de 1 l equivalen al 10% del envase.
  ({String dimension, double factor}) unitInfo(String raw) {
    final u = raw.trim().toLowerCase().replaceAll(' ', '');
    switch (u) {
      case 'kg': case 'kilo': case 'kilos': case 'kilogramo': case 'kilogramos':
        return (dimension: 'mass', factor: 1000);
      case 'g': case 'gr': case 'gramo': case 'gramos':
        return (dimension: 'mass', factor: 1);
      case 'l': case 'lt': case 'lts': case 'litro': case 'litros':
        return (dimension: 'volume', factor: 1000);
      case 'ml': case 'cc': case 'mililitro': case 'mililitros':
        return (dimension: 'volume', factor: 1);
      case 'unidad': case 'unidades': case 'u': case 'unid':
        return (dimension: 'count', factor: 1);
      default:
        return (dimension: 'other:' + u, factor: 1);
    }
  }

  double ingredientCost({
    required double usedQty,
    required String usedUnit,
    required double packQty,
    required String packUnit,
    required double price,
  }) {
    if (packQty <= 0 || usedQty < 0 || price < 0) return 0;
    final used = unitInfo(usedUnit);
    final pack = unitInfo(packUnit);
    if (used.dimension != pack.dimension) {
      throw StateError('Unidades incompatibles: $usedUnit y $packUnit');
    }
    // El precio guardado corresponde al envase completo. Convertimos ambas
    // cantidades a la misma unidad base antes de calcular la proporción.
    final usedInBase = usedQty * used.factor;
    final packInBase = packQty * pack.factor;
    if (packInBase <= 0) return 0;
    return (price / packInBase) * usedInBase;
  }

  Future<double> cost(Map<String,Object?> recipe) async {
    final rows=await Store.instance.db.rawQuery('SELECT ri.qty,ri.unit,i.price,i.qty AS pack_qty,i.unit AS pack_unit FROM recipe_items ri JOIN ingredients i ON i.id=ri.ingredient_id WHERE ri.recipe_id=?',[recipe['id']]);
    double total=0;
    for(final x in rows){
      total += ingredientCost(
        usedQty: (x['qty'] as num).toDouble(),
        usedUnit: x['unit'] as String,
        packQty: (x['pack_qty'] as num).toDouble(),
        packUnit: x['pack_unit'] as String,
        price: (x['price'] as num).toDouble(),
      );
    }
    final settings=await Store.instance.db.query('settings',where:'key=?',whereArgs:['hourly_rate'],limit:1);
    final rate=settings.isEmpty?0:number(settings.first['value'] as String);
    total+=(recipe['minutes'] as num).toDouble()/60*rate;
    return total;
  }
  Future<void> add() async {
    await editDialog(context,'Nueva receta',[
      FormFieldSpec('name','Nombre',initial:query.trim()),const FormFieldSpec('description','Descripción',required:false),const FormFieldSpec('minutes','Tiempo de preparación (min)',numeric:true),const FormFieldSpec('yield_qty','Cantidad que rinde',numeric:true),const FormFieldSpec('yield_unit','Unidad del rendimiento',options:['g','kg','ml','l','cc','unidad']),const FormFieldSpec('sale_qty','Presentación de venta',numeric:true),const FormFieldSpec('sale_unit','Unidad de presentación',options:['g','kg','ml','l','cc','unidad']),const FormFieldSpec('sale_price','Precio de venta',numeric:true),
    ],(v)async{final name=titleCase(v['name']??'');final dup=await Store.instance.db.query('recipes',where:'LOWER(name)=?',whereArgs:[name.toLowerCase()],limit:1);if(dup.isNotEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ya existe una receta con ese nombre.')));return;}final now=stamp();final price=number(v['sale_price']);final id=await Store.instance.db.insert('recipes',{'name':name,'description':v['description']??'','minutes':number(v['minutes']),'yield_qty':number(v['yield_qty']),'yield_unit':v['yield_unit'],'sale_qty':number(v['sale_qty']),'sale_unit':v['sale_unit'],'sale_price':price,'updated':now,'sale_updated':now});await Store.instance.db.insert('recipe_prices',{'recipe_id':id,'price':price,'date':now});if(mounted)setState((){});widget.onChange();});
  }
  Future<void> addIngredient(Map<String,Object?> recipe) async {
    final ingredients=await Store.instance.db.query('ingredients',orderBy:'name COLLATE NOCASE');
    if(ingredients.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Primero cargá un insumo.')));return;}
    Map<String,Object?>? chosen;
    String unit='g';
    final qty=TextEditingController(text:'1');
    final search=TextEditingController();
    if(!mounted)return;
    await showDialog<void>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:const Text('Agregar ingrediente'),
      content:SizedBox(width:400,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Autocomplete<Map<String,Object?>>(
          displayStringForOption:(x)=>x['name'] as String,
          optionsBuilder:(value) {
            final q=value.text.trim().toLowerCase();
            return ingredients.where((x)=>(x['name'] as String).toLowerCase().contains(q));
          },
          fieldViewBuilder:(context,controller,focusNode,onFieldSubmitted) {
            search.text=controller.text;
            return TextField(
              controller:controller,
              focusNode:focusNode,
              decoration:InputDecoration(
                labelText:'Buscar insumo',
                hintText:'Escribí el nombre',
                prefixIcon:const Icon(Icons.search),
                suffixIcon:controller.text.isEmpty?null:IconButton(
                  icon:const Icon(Icons.clear),
                  onPressed:(){controller.clear();setD(()=>chosen=null);},
                ),
              ),
            );
          },
          onSelected:(option)=>setD(()=>chosen=option),
          optionsViewBuilder:(context,onSelected,options)=>Align(
            alignment:Alignment.topLeft,
            child:Material(
              elevation:4,
              child:ConstrainedBox(
                constraints:const BoxConstraints(maxHeight:220,maxWidth:360),
                child:ListView(
                  padding:EdgeInsets.zero,
                  shrinkWrap:true,
                  children:options.map((option)=>ListTile(
                    title:Text(option['name'] as String),
                    subtitle:Text('Presentación: ${option['qty']} ${option['unit']} · ${cash(option['price'] as num)}'),
                    onTap:()=>onSelected(option),
                  )).toList(),
                ),
              ),
            ),
          ),
        ),
        if(chosen!=null)Padding(
          padding:const EdgeInsets.only(top:8),
          child:Align(alignment:Alignment.centerLeft,child:Text('Seleccionado: ${chosen!['name']}')),
        ),
        const SizedBox(height:12),
        TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Cantidad usada')),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(
          value:unit,
          decoration:const InputDecoration(labelText:'Unidad utilizada'),
          items:const ['g','kg','ml','l','unidad'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
          onChanged:(v){if(v!=null)setD(()=>unit=v);},
        ),
      ]))),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
        FilledButton(onPressed:()async{
          final q=number(qty.text);
          if(chosen==null){
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Buscá y seleccioná un insumo.')));
            return;
          }
          if(q<=0){
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ingresá una cantidad mayor que cero.')));
            return;
          }
          try {
            ingredientCost(usedQty:q,usedUnit:unit,packQty:(chosen!['qty'] as num).toDouble(),packUnit:chosen!['unit'] as String,price:(chosen!['price'] as num).toDouble());
          } on StateError {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('La unidad elegida ($unit) no es compatible con la presentación del insumo (${chosen!['unit']}).')));
            return;
          }
          final already=await Store.instance.db.query('recipe_items',where:'recipe_id=? AND ingredient_id=?',whereArgs:[recipe['id'],chosen!['id']],limit:1);
          if(already.isNotEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ese insumo ya está incluido en la receta. Editá su cantidad desde la lista.')));return;}
          await Store.instance.db.insert('recipe_items',{'recipe_id':recipe['id'],'ingredient_id':chosen!['id'],'qty':q,'unit':unit});
          if(ctx.mounted)Navigator.pop(ctx);
          if(mounted)setState((){});
          widget.onChange();
        },child:const Text('Agregar')),
      ],
    )));
    qty.dispose();
    search.dispose();
  }
  Future<void> editIngredientItem(Map<String,Object?> recipe, Map<String,Object?> item) async {
    final ingredients = await Store.instance.db.query('ingredients', orderBy:'name COLLATE NOCASE');
    if (ingredients.isEmpty) return;
    final current = ingredients.where((x) => x['id'] == item['ingredient_id']).toList();
    Map<String,Object?>? chosen = current.isEmpty ? ingredients.first : current.first;
    final qty = TextEditingController(text:item['qty'].toString());
    String unit = item['unit'] as String;
    final searchController = TextEditingController(text:chosen['name'] as String);
    if (!mounted) return;
    await showDialog<void>(
      context:context,
      builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
        title:const Text('Editar ingrediente'),
        content:SizedBox(width:400, child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          Autocomplete<Map<String,Object?>>(
            initialValue: TextEditingValue(text: chosen!['name'] as String),
            displayStringForOption:(x)=>x['name'] as String,
            optionsBuilder:(v) {
              final q=v.text.trim().toLowerCase();
              return ingredients.where((x)=>(x['name'] as String).toLowerCase().contains(q));
            },
            onSelected:(x)=>setD(()=>chosen=x),
            fieldViewBuilder:(context,controller,focusNode,onSubmitted)=>TextField(
              controller:controller, focusNode:focusNode,
              decoration:const InputDecoration(labelText:'Buscar insumo',prefixIcon:Icon(Icons.search)),
              onChanged:(v){ if(chosen != null && v != chosen!['name']) setD(()=>chosen=null); },
            ),
          ),
          if(chosen!=null) Align(alignment:Alignment.centerLeft,child:Text('Presentación: ${chosen!['qty']} ${chosen!['unit']} · envase: ${cash(chosen!['price'] as num)}')),
          const SizedBox(height:12),
          TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Cantidad usada')),
          const SizedBox(height:12),
          DropdownButtonFormField<String>(
            value:['g','kg','ml','l','unidad'].contains(unit)?unit:'g',
            decoration:const InputDecoration(labelText:'Unidad utilizada'),
            items:const ['g','kg','ml','l','unidad'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
            onChanged:(v){if(v!=null)setD(()=>unit=v);},
          ),
        ]))),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
          TextButton(
            style:TextButton.styleFrom(foregroundColor:Theme.of(context).colorScheme.error),
            onPressed:()async{
              await Store.instance.db.delete('recipe_items',where:'id=?',whereArgs:[item['id']]);
              if(ctx.mounted)Navigator.pop(ctx);
              if(mounted)setState((){});
              widget.onChange();
            },
            child:const Text('Quitar ingrediente'),
          ),
          FilledButton(onPressed:()async{
            final q=number(qty.text);
            if(chosen==null || q<=0){
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Seleccioná un insumo e ingresá una cantidad mayor que cero.')));
              return;
            }
            try {
              ingredientCost(usedQty:q,usedUnit:unit,packQty:(chosen!['qty'] as num).toDouble(),packUnit:chosen!['unit'] as String,price:(chosen!['price'] as num).toDouble());
            } on StateError {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('La unidad usada ($unit) no coincide con la presentación (${chosen!['unit']}).')));
              return;
            }
            await Store.instance.db.update('recipe_items',{'ingredient_id':chosen!['id'],'qty':q,'unit':unit},where:'id=?',whereArgs:[item['id']]);
            if(ctx.mounted)Navigator.pop(ctx);
            if(mounted)setState((){});
            widget.onChange();
          },child:const Text('Guardar cambios')),
        ],
      )),
    );
    qty.dispose();
    searchController.dispose();
  }

  Future<void> editRecipe(Map<String,Object?> r) async {
    await editDialog(context,'Editar receta',[FormFieldSpec('name','Nombre',initial:r['name'] as String),FormFieldSpec('description','Descripción',initial:r['description'] as String,required:false),FormFieldSpec('minutes','Tiempo de preparación (min)',initial:r['minutes'].toString(),numeric:true),FormFieldSpec('yield_qty','Cantidad que rinde',initial:r['yield_qty'].toString(),numeric:true),const FormFieldSpec('yield_unit','Unidad del rendimiento',options:['g','kg','ml','l','cc','unidad']),FormFieldSpec('sale_qty','Presentación de venta',initial:r['sale_qty'].toString(),numeric:true),const FormFieldSpec('sale_unit','Unidad de presentación',options:['g','kg','ml','l','cc','unidad']),FormFieldSpec('sale_price','Precio de venta',initial:r['sale_price'].toString(),numeric:true)],(v)async{final name=titleCase(v['name']??'');final dup=await Store.instance.db.query('recipes',where:'LOWER(name)=? AND id<>?',whereArgs:[name.toLowerCase(),r['id']],limit:1);if(dup.isNotEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ya existe una receta con ese nombre.')));return;}final now=stamp();final price=number(v['sale_price']);await Store.instance.db.update('recipes',{'name':name,'description':v['description']??'','minutes':number(v['minutes']),'yield_qty':number(v['yield_qty']),'yield_unit':v['yield_unit'],'sale_qty':number(v['sale_qty']),'sale_unit':v['sale_unit'],'sale_price':price,'updated':now,'sale_updated':now},where:'id=?',whereArgs:[r['id']]);if(price!=(r['sale_price'] as num).toDouble())await Store.instance.db.insert('recipe_prices',{'recipe_id':r['id'],'price':price,'date':now});if(mounted)setState((){});widget.onChange();});
  }
  Future<void> editSale(Map<String,Object?> r) async {
    await editDialog(context,'Precio y presentación',[
      FormFieldSpec('qty','Cantidad de venta',initial:r['sale_qty'].toString(),numeric:true),
      FormFieldSpec('unit','Unidad de venta',initial:r['sale_unit'] as String),
      FormFieldSpec('price','Precio de venta',initial:r['sale_price'].toString(),numeric:true),
    ],(v)async{await Store.instance.db.update('recipes',{'sale_qty':number(v['qty']),'sale_unit':v['unit'],'sale_price':number(v['price']),'sale_updated':stamp()},where:'id=?',whereArgs:[r['id']]);if(mounted)setState((){});widget.onChange();});
  }
  Future<void> detail(Map<String,Object?> r) async {
    final items=await Store.instance.db.rawQuery('SELECT ri.id,ri.recipe_id,ri.ingredient_id,ri.qty,ri.unit,i.name,i.price,i.qty AS pack_qty,i.unit AS pack_unit FROM recipe_items ri JOIN ingredients i ON i.id=ri.ingredient_id WHERE ri.recipe_id=?',[r['id']]);
    final saleHistory=await Store.instance.db.query('recipe_prices',where:'recipe_id=?',whereArgs:[r['id']],orderBy:'date DESC');
    final c=await cost(r);final sale=(r['sale_price'] as num).toDouble();final settings=await Store.instance.db.query('settings',where:'key=?',whereArgs:['ideal_margin'],limit:1);final ideal=settings.isEmpty?60.0:number(settings.first['value'] as String);final yieldInfo=unitInfo(r['yield_unit'] as String);final saleInfo=unitInfo(r['sale_unit'] as String);final compatible=yieldInfo.dimension==saleInfo.dimension;final saleCost=compatible&&(yieldInfo.factor*(r['yield_qty'] as num).toDouble()>0)?c*((r['sale_qty'] as num).toDouble()*saleInfo.factor/((r['yield_qty'] as num).toDouble()*yieldInfo.factor)):double.nan;final margin=sale>0?(sale-saleCost)/sale*100:0;
    if(!mounted)return;
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text(r['name'] as String),content:SizedBox(width:400,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text((r['description'] as String).isEmpty?'Sin descripción':r['description'] as String),
      Text('Tiempo de preparación: ${fmt(r['minutes'] as num)} min'),Text('Rendimiento: ${fmt(r['yield_qty'] as num)} ${r['yield_unit']}'),Text('Costo estimado de la receta: '+cash(c),style:const TextStyle(fontWeight:FontWeight.bold)),Text('Presentación de venta: ${fmt(r['sale_qty'] as num)} ${r['sale_unit']}'),Text('Costo estimado de la presentación: '+(compatible?cash(saleCost):'Unidades incompatibles')),Text('Precio de venta: '+cash(sale)),Text('Margen de contribución: ${fmt(margin)}%',style:TextStyle(color:margin<=0?Colors.red:margin<ideal?Colors.orange:null)),Text('Última actualización: '+dateLabel(r['updated'] as String)),
      const Divider(),const Text('Ingredientes',style:TextStyle(fontWeight:FontWeight.bold)),
      if(items.isEmpty)const Text('Agregá ingredientes para calcular el costo.'),
      ...items.map((x) {
        double usedCost = 0;
        try {
          usedCost = ingredientCost(
            usedQty:(x['qty'] as num).toDouble(),
            usedUnit:x['unit'] as String,
            packQty:(x['pack_qty'] as num).toDouble(),
            packUnit:x['pack_unit'] as String,
            price:(x['price'] as num).toDouble(),
          );
        } on StateError {}
        return ListTile(
          contentPadding:EdgeInsets.zero,
          title:Text(x['name'] as String),
          subtitle:Text('${x['qty']} ${x['unit']} usados · costo de esta cantidad: ${cash(usedCost)}\nEnvase: ${x['pack_qty']} ${x['pack_unit']} = ${cash(x['price'] as num)}'),
          isThreeLine:true,
          trailing:IconButton(icon:const Icon(Icons.edit_outlined),tooltip:'Editar ingrediente',onPressed:()async{Navigator.pop(ctx);await editIngredientItem(r,x);await detail(r);}),
        );
      }),
    ]))), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
      TextButton(onPressed: () async { Navigator.pop(ctx); if(!mounted)return; await showDialog<void>(context:context,builder:(h)=>AlertDialog(title:Text('Historial de venta · ${r['name']}'),content:SizedBox(width:320,child:saleHistory.isEmpty?const Text('Sin historial registrado.'):ListView(shrinkWrap:true,children:saleHistory.map((x)=>ListTile(title:Text(cash(x['price'] as num)),subtitle:Text(dateLabel(x['date'] as String)))).toList())),actions:[TextButton(onPressed:()=>Navigator.pop(h),child:const Text('Cerrar'))])); }, child: const Text('Historial de precios')),
      TextButton(onPressed: () async { Navigator.pop(ctx); await editRecipe(r); }, child: const Text('Editar receta')),
      FilledButton(onPressed: () async { Navigator.pop(ctx); await addIngredient(r); }, child: const Text('Agregar ingrediente')),
    ]));
  }
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:TextField(controller:searchController,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar o registrar receta',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>query=v))),
    Expanded(child:FutureBuilder<List<Map<String,Object?>>>(future:data,builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final list=s.data!.where((r)=>(r['name'] as String).toLowerCase().contains(query.toLowerCase())).toList();final exact=list.any((r)=>(r['name'] as String).toLowerCase()==query.trim().toLowerCase());final canCreate=query.trim().isNotEmpty&&!exact;if(list.isEmpty&&!canCreate)return const Center(child:Text('Buscá una receta por su nombre.'));return ListView(children:[if(canCreate)Card(child:ListTile(leading:const Icon(Icons.add_circle_outline),title:Text('Registrar ${titleCase(query)}'),subtitle:const Text('Crear una receta nueva'),onTap:add)),...list.map((r)=>FutureBuilder<int>(future:Store.instance.db.query('recipe_items',where:'recipe_id=?',whereArgs:[r['id']]).then((x)=>x.length),builder:(c,count)=>Card(child:ListTile(title:Text(r['name'] as String),subtitle:(count.data??0)==0?const Text('⚠ Agregá ingredientes para calcular el costo',style:TextStyle(color:Colors.orange)):FutureBuilder<double>(future:cost(r),builder:(c,cs)=>Text('Costo: ${cs.hasData?cash(cs.data!):'…'} · Venta: ${cash(r['sale_price'] as num)}')),trailing:const Icon(Icons.chevron_right),onTap:()=>detail(r))))) ]); })),
  ]);
  @override void dispose(){searchController.dispose();super.dispose();}
}

class SettingsPage extends StatefulWidget { const SettingsPage({super.key}); @override State<SettingsPage> createState()=>_SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage> {
  final rate=TextEditingController();final margin=TextEditingController();bool ready=false;
  Future<void> load() async {
    final rows=await Store.instance.db.query('settings');
    for(final r in rows){if(r['key']=='hourly_rate')rate.text=r['value'] as String;if(r['key']=='ideal_margin')margin.text=r['value'] as String;}
    if(mounted)setState(()=>ready=true);
  }
  @override void initState(){super.initState();load();}
  Future<void> save() async {
    await Store.instance.db.update('settings',{'value':number(rate.text).toString()},where:'key=?',whereArgs:['hourly_rate']);
    await Store.instance.db.update('settings',{'value':number(margin.text).toString()},where:'key=?',whereArgs:['ideal_margin']);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Parámetros guardados.')));
  }
  @override Widget build(BuildContext context)=>!ready?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(20),children:[
    const Text('Configurá los valores que se usan para estimar tus costos.'),
    const SizedBox(height:24),TextField(controller:rate,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Valor de la hora de trabajo',prefixText:'\$ ',helperText:'En pesos argentinos')),
    const SizedBox(height:18),TextField(controller:margin,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Margen de contribución ideal',suffixText:'%',helperText:'Objetivo sobre el precio de venta')),
    const SizedBox(height:24),FilledButton.icon(onPressed:save,icon:const Icon(Icons.save_outlined),label:const Text('Guardar parámetros')),
    const SizedBox(height:24),const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Margen de contribución = (precio de venta − costo estimado) ÷ precio de venta. El costo estimado incluye insumos y mano de obra.'))),
  ]);
  @override void dispose(){rate.dispose();margin.dispose();super.dispose();}
}
