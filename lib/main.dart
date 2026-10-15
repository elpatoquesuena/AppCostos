import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.open();
  runApp(const CostosApp());
}

class Store {
  Store._();
  static final Store instance = Store._();
  late Database db;
  Future<void> open() async {
    db = await openDatabase(path.join(await getDatabasesPath(), 'app_costos.db'),
      version: 1,
      onCreate: (d, v) async {
        await d.execute('CREATE TABLE ingredients(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,description TEXT NOT NULL DEFAULT "",qty REAL NOT NULL,unit TEXT NOT NULL,price REAL NOT NULL,updated TEXT NOT NULL)');
        await d.execute('CREATE TABLE ingredient_prices(id INTEGER PRIMARY KEY AUTOINCREMENT,ingredient_id INTEGER NOT NULL,price REAL NOT NULL,date TEXT NOT NULL)');
        await d.execute('CREATE TABLE recipes(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,description TEXT NOT NULL DEFAULT "",minutes REAL NOT NULL DEFAULT 0,yield_qty REAL NOT NULL DEFAULT 1,yield_unit TEXT NOT NULL DEFAULT "unidad",sale_qty REAL NOT NULL DEFAULT 1,sale_unit TEXT NOT NULL DEFAULT "unidad",sale_price REAL NOT NULL DEFAULT 0,updated TEXT NOT NULL,sale_updated TEXT NOT NULL)');
        await d.execute('CREATE TABLE recipe_items(id INTEGER PRIMARY KEY AUTOINCREMENT,recipe_id INTEGER NOT NULL,ingredient_id INTEGER NOT NULL,qty REAL NOT NULL,unit TEXT NOT NULL)');
        await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)');
        await d.insert('settings', {'key':'hourly_rate','value':'0'});
        await d.insert('settings', {'key':'ideal_margin','value':'60'});
      });
  }
}

String cash(num n) => '\$' + n.toStringAsFixed(2);
String stamp() => DateTime.now().toIso8601String();
String dateLabel(String value) {
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  return d.day.toString().padLeft(2,'0') + '/' + d.month.toString().padLeft(2,'0') + '/' + d.year.toString();
}
double number(String? s) => double.tryParse((s ?? '').replaceAll(',', '.')) ?? 0;

class CostosApp extends StatelessWidget {
  const CostosApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'AppCostos', debugShowCheckedModeBanner: false,
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
    return Scaffold(
      appBar: AppBar(title: const Text('AppCostos')),
      body: IndexedStack(index:index, children:pages),
      bottomNavigationBar: NavigationBar(selectedIndex:index,onDestinationSelected:(i)=>setState(()=>index=i),destinations:const [
        NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'Inicio'),
        NavigationDestination(icon:Icon(Icons.inventory_2_outlined),label:'Insumos'),
        NavigationDestination(icon:Icon(Icons.menu_book_outlined),label:'Recetas'),
        NavigationDestination(icon:Icon(Icons.tune),label:'Parámetros'),
      ]),
    );
  }
}

class Dashboard extends StatelessWidget {
  final ValueChanged<int> go;
  const Dashboard({super.key,required this.go});
  @override Widget build(BuildContext context) => ListView(padding:const EdgeInsets.all(20),children:[
    const Text('Costeá mejor. Decidí con datos.',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),const Text('Controlá los precios de tus insumos y calculá el costo de tus recetas.'),
    const SizedBox(height:20),
    FutureBuilder<List<int>>(future:Future.wait([
      Store.instance.db.rawQuery('SELECT COUNT(*) c FROM ingredients').then((r)=>r.first['c'] as int),
      Store.instance.db.rawQuery('SELECT COUNT(*) c FROM recipes').then((r)=>r.first['c'] as int),
    ]),builder:(c,s)=>Row(children:[
      Expanded(child:Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.inventory_2_outlined,size:28),const SizedBox(height:10),Text(s.hasData?s.data![0].toString():'…',style:const TextStyle(fontSize:28,fontWeight:FontWeight.bold)),const Text('Insumos')])))),
      const SizedBox(width:12),
      Expanded(child:Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.menu_book_outlined,size:28),const SizedBox(height:10),Text(s.hasData?s.data![1].toString():'…',style:const TextStyle(fontSize:28,fontWeight:FontWeight.bold)),const Text('Recetas')])))),
    ])),
    const SizedBox(height:12),
    Card(child:ListTile(leading:const Icon(Icons.add_circle_outline),title:const Text('Cargar insumo'),subtitle:const Text('Registrá presentación y precio'),trailing:const Icon(Icons.chevron_right),onTap:()=>go(1))),
    Card(child:ListTile(leading:const Icon(Icons.post_add),title:const Text('Crear receta'),subtitle:const Text('Definí rendimiento, costo y precio de venta'),trailing:const Icon(Icons.chevron_right),onTap:()=>go(2))),
    Card(child:ListTile(leading:const Icon(Icons.tune),title:const Text('Parámetros'),subtitle:const Text('Valor hora y margen ideal'),trailing:const Icon(Icons.chevron_right),onTap:()=>go(3))),
    const SizedBox(height:12),const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Actualizá el precio de los insumos cada vez que comprás para mantener los costos al día.'))),
  ]);
}

Future<void> editDialog(BuildContext context, String title, List<FormFieldSpec> fields, Future<void> Function(Map<String,String>) onSave) async {
  final controllers = <String,TextEditingController>{for(final f in fields) f.key:TextEditingController(text:f.initial)};
  final key = GlobalKey<FormState>();
  await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
    title:Text(title),
    content:SizedBox(width:400,child:SingleChildScrollView(child:Form(key:key,child:Column(mainAxisSize:MainAxisSize.min,children:fields.map((f)=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextFormField(controller:controllers[f.key],keyboardType:f.numeric?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,decoration:InputDecoration(labelText:f.label),validator:f.required?(v)=>(v==null||v.trim().isEmpty)?'Campo obligatorio':null:null)).toList())))),
    actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),FilledButton(onPressed:()async{if(!key.currentState!.validate())return;final values={for(final e in controllers.entries)e.key:e.value.text.trim()};Navigator.pop(ctx);await onSave(values);},child:const Text('Guardar'))],
  ));
  for(final c in controllers.values){c.dispose();}
}
class FormFieldSpec {
  final String key,label,initial; final bool numeric,required;
  const FormFieldSpec(this.key,this.label,{this.initial='',this.numeric=false,this.required=true});
}

class IngredientsPage extends StatefulWidget {
  final VoidCallback onChange;
  const IngredientsPage({super.key,required this.onChange});
  @override State<IngredientsPage> createState()=>_IngredientsPageState();
}
class _IngredientsPageState extends State<IngredientsPage> {
  String query='';
  Future<List<Map<String,Object?>>> get data=>Store.instance.db.query('ingredients',orderBy:'name COLLATE NOCASE');
  Future<void> add() async {
    await editDialog(context,'Nuevo insumo',const [
      FormFieldSpec('name','Nombre'),FormFieldSpec('description','Descripción',required:false),
      FormFieldSpec('qty','Cantidad de la presentación',initial:'1',numeric:true),FormFieldSpec('unit','Unidad (g, kg, ml, l, unidad)',initial:'g'),
      FormFieldSpec('price','Precio pagado',numeric:true),
    ],(v)async{
      final now=stamp();final price=number(v['price']);
      final id=await Store.instance.db.insert('ingredients',{'name':v['name'],'description':v['description']??'','qty':number(v['qty']),'unit':v['unit'],'price':price,'updated':now});
      await Store.instance.db.insert('ingredient_prices',{'ingredient_id':id,'price':price,'date':now});
      if(mounted)setState((){});widget.onChange();
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
      const SizedBox(height:8),Text('Presentación: '+item['qty'].toString()+' '+(item['unit'] as String)),
      Text('Precio actual: '+cash(item['price'] as num)),Text('Actualizado: '+dateLabel(item['updated'] as String)),
      const Divider(),const Text('Historial de precios',style:TextStyle(fontWeight:FontWeight.bold)),
      ...history.map((h)=>ListTile(contentPadding:EdgeInsets.zero,title:Text(cash(h['price'] as num)),subtitle:Text(dateLabel(h['date'] as String)))),
      const Divider(),const Text('Recetas que lo usan',style:TextStyle(fontWeight:FontWeight.bold)),
      if(recipes.isEmpty)const Text('Ninguna por ahora.'),...recipes.map((r)=>Text('• '+(r['name'] as String))),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cerrar'))]);
  }
  Future<void> remove(Map<String,Object?> item) async {
    final used=await Store.instance.db.query('recipe_items',where:'ingredient_id=?',whereArgs:[item['id']],limit:1);
    if(used.isNotEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No se puede eliminar: está asociado a una receta.')));return;}
    if(!mounted)return;
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Eliminar insumo'),content:Text('¿Eliminar '+(item['name'] as String)+'?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Eliminar'))]));
    if(yes==true){await Store.instance.db.delete('ingredient_prices',where:'ingredient_id=?',whereArgs:[item['id']]);await Store.instance.db.delete('ingredients',where:'id=?',whereArgs:[item['id']]);if(mounted)setState((){});widget.onChange();}
  }
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar insumo'),onChanged:(v)=>setState(()=>query=v))),const SizedBox(width:8),IconButton.filled(onPressed:add,icon:const Icon(Icons.add),tooltip:'Nuevo insumo')])),
    Expanded(child:FutureBuilder<List<Map<String,Object?>>>(future:data,builder:(c,s){
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final list=s.data!.where((x)=>(x['name'] as String).toLowerCase().contains(query.toLowerCase())).toList();
      if(list.isEmpty)return const Center(child:Text('No hay insumos. Tocá + para agregar uno.'));
      return ListView.builder(itemCount:list.length,itemBuilder:(c,i){final x=list[i];return Card(child:ListTile(title:Text(x['name'] as String),subtitle:Text(x['qty'].toString()+' '+(x['unit'] as String)+' · '+dateLabel(x['updated'] as String)),leading:IconButton(onPressed:()=>priceUpdate(x),icon:const Icon(Icons.price_change_outlined)),trailing:Text(cash(x['price'] as num),style:const TextStyle(fontWeight:FontWeight.bold)),onTap:()=>detail(x),onLongPress:()=>remove(x)));});
    })),
  ]);
}

class RecipesPage extends StatefulWidget {
  final VoidCallback onChange;
  const RecipesPage({super.key,required this.onChange});
  @override State<RecipesPage> createState()=>_RecipesPageState();
}
class _RecipesPageState extends State<RecipesPage> {
  Future<List<Map<String,Object?>>> get data=>Store.instance.db.query('recipes',orderBy:'name COLLATE NOCASE');
  Future<double> cost(Map<String,Object?> recipe) async {
    final rows=await Store.instance.db.rawQuery('SELECT ri.qty,ri.unit,i.price,i.qty AS pack_qty,i.unit AS pack_unit FROM recipe_items ri JOIN ingredients i ON i.id=ri.ingredient_id WHERE ri.recipe_id=?',[recipe['id']]);
    double total=0;
    for(final x in rows){
      final used=(x['qty'] as num).toDouble();final pack=(x['pack_qty'] as num).toDouble();final price=(x['price'] as num).toDouble();
      final u=x['unit'] as String;final pu=x['pack_unit'] as String;
      double normalized=used;
      if(u=='kg'&&pu=='g'||u=='l'&&pu=='ml')normalized=used*1000;
      if(u=='g'&&pu=='kg'||u=='ml'&&pu=='l')normalized=used/1000;
      total+=price*normalized/pack;
    }
    final settings=await Store.instance.db.query('settings',where:'key=?',whereArgs:['hourly_rate'],limit:1);
    final rate=settings.isEmpty?0:number(settings.first['value'] as String);
    total+=(recipe['minutes'] as num).toDouble()/60*rate;
    return total;
  }
  Future<void> add() async {
    await editDialog(context,'Nueva receta',const [
      FormFieldSpec('name','Nombre'),FormFieldSpec('description','Descripción',required:false),
      FormFieldSpec('minutes','Tiempo de preparación (min)',initial:'0',numeric:true),
      FormFieldSpec('yield_qty','Rendimiento: cantidad',initial:'1',numeric:true),FormFieldSpec('yield_unit','Rendimiento: unidad',initial:'unidad'),
      FormFieldSpec('sale_qty','Presentación de venta: cantidad',initial:'1',numeric:true),FormFieldSpec('sale_unit','Presentación de venta: unidad',initial:'unidad'),
      FormFieldSpec('sale_price','Precio de venta',initial:'0',numeric:true),
    ],(v)async{final now=stamp();await Store.instance.db.insert('recipes',{'name':v['name'],'description':v['description']??'','minutes':number(v['minutes']),'yield_qty':number(v['yield_qty']),'yield_unit':v['yield_unit'],'sale_qty':number(v['sale_qty']),'sale_unit':v['sale_unit'],'sale_price':number(v['sale_price']),'updated':now,'sale_updated':now});if(mounted)setState((){});widget.onChange();});
  }
  Future<void> addIngredient(Map<String,Object?> recipe) async {
    final ingredients=await Store.instance.db.query('ingredients',orderBy:'name COLLATE NOCASE');
    if(ingredients.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Primero cargá un insumo.')));return;}
    int chosen=ingredients.first['id'] as int;String unit='g';final qty=TextEditingController(text:'1');
    if(!mounted)return;
    await showDialog<void>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(title:const Text('Agregar ingrediente'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<int>(value:chosen,decoration:const InputDecoration(labelText:'Insumo'),items:ingredients.map((x)=>DropdownMenuItem(value:x['id'] as int,child:Text(x['name'] as String,overflow:TextOverflow.ellipsis))).toList(),onChanged:(v){if(v!=null)setD(()=>chosen=v);}),
      const SizedBox(height:12),TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Cantidad usada')),
      const SizedBox(height:12),DropdownButtonFormField<String>(value:unit,decoration:const InputDecoration(labelText:'Unidad'),items:const ['g','kg','ml','l','unidad'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v){if(v!=null)setD(()=>unit=v);}),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),FilledButton(onPressed:()async{final q=number(qty.text);if(q<=0)return;await Store.instance.db.insert('recipe_items',{'recipe_id':recipe['id'],'ingredient_id':chosen,'qty':q,'unit':unit});if(ctx.mounted)Navigator.pop(ctx);if(mounted)setState((){});widget.onChange();},child:const Text('Agregar')]))));
    qty.dispose();
  }
  Future<void> editSale(Map<String,Object?> r) async {
    await editDialog(context,'Precio y presentación',[
      FormFieldSpec('qty','Cantidad de venta',initial:r['sale_qty'].toString(),numeric:true),
      FormFieldSpec('unit','Unidad de venta',initial:r['sale_unit'] as String),
      FormFieldSpec('price','Precio de venta',initial:r['sale_price'].toString(),numeric:true),
    ],(v)async{await Store.instance.db.update('recipes',{'sale_qty':number(v['qty']),'sale_unit':v['unit'],'sale_price':number(v['price']),'sale_updated':stamp()},where:'id=?',whereArgs:[r['id']]);if(mounted)setState((){});widget.onChange();});
  }
  Future<void> detail(Map<String,Object?> r) async {
    final items=await Store.instance.db.rawQuery('SELECT ri.id,ri.qty,ri.unit,i.name,i.price FROM recipe_items ri JOIN ingredients i ON i.id=ri.ingredient_id WHERE ri.recipe_id=?',[r['id']]);
    final c=await cost(r);final sale=(r['sale_price'] as num).toDouble();final margin=sale>0?(sale-c)/sale*100:0;
    if(!mounted)return;
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text(r['name'] as String),content:SizedBox(width:400,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text((r['description'] as String).isEmpty?'Sin descripción':r['description'] as String),
      Text('Rendimiento: '+r['yield_qty'].toString()+' '+(r['yield_unit'] as String)),
      Text('Venta: '+r['sale_qty'].toString()+' '+(r['sale_unit'] as String)+' · '+cash(sale)),
      Text('Costo estimado: '+cash(c),style:const TextStyle(fontWeight:FontWeight.bold)),
      Text('Margen de contribución: '+margin.toStringAsFixed(1)+'%'),
      Text('Preparación: '+r['minutes'].toString()+' min'),
      const Divider(),const Text('Ingredientes',style:TextStyle(fontWeight:FontWeight.bold)),
      if(items.isEmpty)const Text('Agregá ingredientes para calcular el costo.'),
      ...items.map((x)=>ListTile(contentPadding:EdgeInsets.zero,title:Text(x['name'] as String),subtitle:Text(x['qty'].toString()+' '+(x['unit'] as String)+' · insumo: '+cash(x['price'] as num)))),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cerrar')),TextButton(onPressed:()async{Navigator.pop(ctx);await editSale(r);},child:const Text('Editar venta')),FilledButton(onPressed:()async{Navigator.pop(ctx);await addIngredient(r);},child:const Text('Agregar insumo'))]);
  }
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.all(16),child:Row(children:[const Expanded(child:Text('Tus recetas',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold))),FilledButton.icon(onPressed:add,icon:const Icon(Icons.add),label:const Text('Nueva'))])),
    Expanded(child:FutureBuilder<List<Map<String,Object?>>>(future:data,builder:(c,s){
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      if(s.data!.isEmpty)return const Center(child:Text('Todavía no hay recetas.'));
      return ListView.builder(itemCount:s.data!.length,itemBuilder:(c,i){final r=s.data![i];return FutureBuilder<double>(future:cost(r),builder:(c,cs)=>Card(child:ListTile(title:Text(r['name'] as String),subtitle:Text('Costo: '+(cs.hasData?cash(cs.data!):'…')+' · Venta: '+cash(r['sale_price'] as num)+'\nActualizado: '+dateLabel(r['updated'] as String)),isThreeLine:true,trailing:const Icon(Icons.chevron_right),onTap:()=>detail(r))));});
    })),
  ]);
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
    const Text('Parámetros',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),const Text('Configurá los valores que se usan para estimar tus costos.'),
    const SizedBox(height:24),TextField(controller:rate,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Valor de la hora de trabajo',prefixText:'$ ',helperText:'En pesos argentinos')),
    const SizedBox(height:18),TextField(controller:margin,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Margen de contribución ideal',suffixText:'%',helperText:'Objetivo sobre el precio de venta')),
    const SizedBox(height:24),FilledButton.icon(onPressed:save,icon:const Icon(Icons.save_outlined),label:const Text('Guardar parámetros')),
    const SizedBox(height:24),const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Margen de contribución = (precio de venta − costo estimado) ÷ precio de venta. El costo estimado incluye insumos y mano de obra.'))),
  ]);
  @override void dispose(){rate.dispose();margin.dispose();super.dispose();}
}
