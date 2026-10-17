import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
      await db.insert('ingredient_prices',{'ingredient_id':id,'price':baseUnitPrice(s['price'] as num,s['qty'] as num,s['unit'] as String),'date':now});
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
      version: 4,
      onUpgrade: (d, oldVersion, newVersion) async {
        if(oldVersion<2) await d.execute('CREATE TABLE IF NOT EXISTS recipe_prices(id INTEGER PRIMARY KEY AUTOINCREMENT,recipe_id INTEGER NOT NULL,price REAL NOT NULL,date TEXT NOT NULL)');
        if(oldVersion<3) await d.execute('ALTER TABLE recipes ADD COLUMN portions_per_presentation REAL NOT NULL DEFAULT 1');
        if(oldVersion<4) {
          final ingredients=await d.query('ingredients');
          for(final ingredient in ingredients) {
            final qty=(ingredient['qty'] as num?)?.toDouble() ?? 0;
            final unit=(ingredient['unit'] as String? ?? '').toLowerCase();
            if(qty<=0) continue;
            final factor=['g','gr','gramo','gramos','ml','cc','mililitro','mililitros'].contains(unit)?1000.0:1.0;
            await d.rawUpdate('UPDATE ingredient_prices SET price=price*?/? WHERE ingredient_id=?',[factor,qty,ingredient['id']]);
          }
        }
      },
      onCreate: (d, v) async {
        await d.execute('CREATE TABLE ingredients(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,description TEXT NOT NULL DEFAULT "",qty REAL NOT NULL,unit TEXT NOT NULL,price REAL NOT NULL,updated TEXT NOT NULL)');
        await d.execute('CREATE TABLE ingredient_prices(id INTEGER PRIMARY KEY AUTOINCREMENT,ingredient_id INTEGER NOT NULL,price REAL NOT NULL,date TEXT NOT NULL)');
        await d.execute('CREATE TABLE recipes(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,description TEXT NOT NULL DEFAULT "",minutes REAL NOT NULL DEFAULT 0,yield_qty REAL NOT NULL DEFAULT 1,yield_unit TEXT NOT NULL DEFAULT "unidad",sale_qty REAL NOT NULL DEFAULT 1,sale_unit TEXT NOT NULL DEFAULT "unidad",portions_per_presentation REAL NOT NULL DEFAULT 1,sale_price REAL NOT NULL DEFAULT 0,updated TEXT NOT NULL,sale_updated TEXT NOT NULL)');
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
String cash(num n) => '\$' + fmt(n);

double baseUnitPrice(num presentationPrice, num presentationQty, String rawUnit) {
  final qty=presentationQty.toDouble();
  if(qty<=0)return 0;
  final unit=rawUnit.trim().toLowerCase();
  final multiplier=['g','gr','gramo','gramos','ml','cc','mililitro','mililitros'].contains(unit)?1000.0:1.0;
  return presentationPrice.toDouble()*multiplier/qty;
}
String baseUnitLabel(String rawUnit) {
  final unit=rawUnit.trim().toLowerCase();
  if(['g','gr','gramo','gramos','kg','kilo','kilos','kilogramo','kilogramos'].contains(unit))return 'kg';
  if(['ml','cc','mililitro','mililitros','l','lt','lts','litro','litros'].contains(unit))return 'l';
  return 'unidad';
}

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
String unitDimension(String raw) {
  final u=raw.trim().toLowerCase();
  if(['g','gr','gramo','gramos','kg','kilo','kilos','kilogramo','kilogramos'].contains(u))return 'mass';
  if(['ml','cc','mililitro','mililitros','l','lt','lts','litro','litros'].contains(u))return 'volume';
  if(['unidad','unidades','u','unid'].contains(u))return 'count';
  return 'other:$u';
}

class NumericThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final original=newValue.text;
    final cursor=newValue.selection.isValid ? newValue.selection.extentOffset : original.length;
    final before=original.substring(0,cursor.clamp(0,original.length).toInt());
    final hadComma=original.contains(',');
    String integerPart;
    String fraction='';
    bool hasDecimal=false;
    if(hadComma) {
      final pieces=original.split(',');
      integerPart=pieces.first.replaceAll('.', '').replaceAll(RegExp(r'[^0-9]'), '');
      final rawFraction=pieces.skip(1).join('').replaceAll(RegExp(r'[^0-9]'), '');
      fraction=rawFraction.substring(0,rawFraction.length.clamp(0,2).toInt());
      hasDecimal=true;
    } else if(RegExp(r'^\d{1,3}(\.\d{3})+\d*$').hasMatch(original)) {
      integerPart=original.replaceAll('.', '').replaceAll(RegExp(r'[^0-9]'), '');
    } else if(original.contains('.')) {
      final index=original.lastIndexOf('.');
      integerPart=original.substring(0,index).replaceAll('.', '').replaceAll(RegExp(r'[^0-9]'), '');
      final rawFraction=original.substring(index+1).replaceAll(RegExp(r'[^0-9]'), '');
      fraction=rawFraction.substring(0,rawFraction.length.clamp(0,2).toInt());
      hasDecimal=true;
    } else {
      integerPart=original.replaceAll(RegExp(r'[^0-9]'), '');
    }
    if(integerPart.isEmpty)integerPart='0';
    final grouped=StringBuffer();
    for(var i=0;i<integerPart.length;i++) {
      if(i>0&&(integerPart.length-i)%3==0)grouped.write('.');
      grouped.write(integerPart[i]);
    }
    final formatted=grouped.toString()+(hasDecimal?',$fraction':'');
    final digitsBefore=RegExp(r'\d').allMatches(before).length;
    var newCursor=0;
    var seen=0;
    while(newCursor<formatted.length && seen<digitsBefore) {
      if(RegExp(r'\d').hasMatch(formatted[newCursor]))seen++;
      newCursor++;
    }
    if(before.contains(',') && hasDecimal && digitsBefore>=integerPart.length) {
      newCursor=formatted.indexOf(',')+1+before.substring(before.indexOf(',')+1).replaceAll(RegExp(r'[^0-9]'),'').length;
      if(newCursor>formatted.length)newCursor=formatted.length;
    }
    return TextEditingValue(text:formatted,selection:TextSelection.collapsed(offset:newCursor.clamp(0,formatted.length).toInt()));
  }
}

class CostosApp extends StatelessWidget {
  const CostosApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Costeapp', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF17365D)), scaffoldBackgroundColor: const Color(0xFFF7F8FA), appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF17365D), foregroundColor: Colors.white, elevation: 0), cardTheme: const CardThemeData(color: Colors.white, elevation: 1, margin: EdgeInsets.symmetric(vertical: 6)), filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF17365D), foregroundColor: Colors.white))),
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
      IngredientsPage(onChange: refresh),
      RecipesPage(onChange: refresh),
      const PresupuestoPage(),
      SettingsPage(onDataChanged: refresh),
    ];
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && index != 0 && mounted) {
          setState(() => index = 0);
        }
      },
      child: SafeArea(child: Scaffold(
      appBar: index==0 ? null : AppBar(title: Text(const ['Inicio','Insumos','Recetas','Presupuesto','Parámetros'][index])),
      
      body: IndexedStack(index:index, children:pages),
      bottomNavigationBar: NavigationBar(selectedIndex:index,onDestinationSelected:(i)=>setState(()=>index=i),destinations:const [
        NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'Inicio'),
        NavigationDestination(icon:Icon(Icons.inventory_2_outlined),label:'Insumos'),
        NavigationDestination(icon:Icon(Icons.menu_book_outlined),label:'Recetas'),
        NavigationDestination(icon:Icon(Icons.calculate_outlined),label:'Presupuesto'),
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
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF17365D)),
        ),
        const SizedBox(height: 8),
        const Text('Controlá los precios de tus insumos y calculá el costo de tus recetas.'),
        const SizedBox(height: 12),
        FutureBuilder<String?>(
          future: Store.instance.db.query('settings', columns: ['value'], where: 'key=?', whereArgs: ['hourly_rate_updated'], limit: 1)
              .then((rows) => rows.isEmpty ? null : rows.first['value'] as String?),
          builder: (context, snapshot) {
            if (!snapshot.hasData && !snapshot.hasError) return const SizedBox.shrink();
            final rawDate = snapshot.data;
            final updated = rawDate == null ? null : DateTime.tryParse(rawDate);
            final overdue = updated == null || DateTime.now().difference(updated).inDays > 30;
            if (!overdue) return const SizedBox.shrink();
            final message = updated == null
                ? 'Registrá el valor de la hora de trabajo en Parámetros para mantener tus costos actualizados.'
                : 'El valor de la hora de trabajo lleva más de 30 días sin actualizarse (última actualización: ${dateLabel(rawDate!)}).';
            return Card(
              color: const Color(0xFFFFF3E0),
              child: InkWell(
                onTap: () => go(4),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFF9A5B00), size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Revisá el valor de la hora de trabajo', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF784600))),
                      const SizedBox(height: 4),
                      Text(message, style: const TextStyle(color: Color(0xFF784600))),
                      const SizedBox(height: 6),
                      const Text('Tocá acá para ir a Parámetros.', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF784600))),
                    ])),
                  ]),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
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
                          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFE7EEF7), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.inventory_2_outlined, size: 32, color: Color(0xFF17365D))),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  counts == null ? '…' : counts[0].toString(),
                                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Color(0xFF17365D)),
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
                          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFDCEAF5), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.menu_book_outlined, size: 32, color: Color(0xFF245B86))),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  counts == null ? '…' : counts[1].toString(),
                                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Color(0xFF17365D)),
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
        Card(child: InkWell(onTap: () => go(3), borderRadius: BorderRadius.circular(12), child: const Padding(padding: EdgeInsets.all(20), child: Row(children:[Icon(Icons.calculate_outlined,size:34,color:Color(0xFF245B86)),SizedBox(width:16),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Presupuesto',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:Color(0xFF17365D))),SizedBox(height:4),Text('Calculá costos y precios según las porciones que necesitás.')])),Icon(Icons.arrow_forward,color:Color(0xFF17365D))])))),
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

Future<void> editDialog(BuildContext context,String title,List<FormFieldSpec> fields,Future<void> Function(Map<String,String>) onSave,{Future<void> Function()? onDelete}) async {
  final controllers=<String,TextEditingController>{for(final f in fields)f.key:TextEditingController(text:f.initial)};
  final selected=<String,String>{for(final f in fields.where((x)=>x.options!=null))f.key:(f.options!.contains(f.initial)?f.initial:f.options!.first)};
  final formKey=GlobalKey<FormState>();
  var confirmingDelete=false;
  List<String> optionsFor(FormFieldSpec f) {
    final options=f.options??const <String>[];
    if(f.key=='sale_unit'&&selected.containsKey('yield_unit')) {
      final compatible=options.where((o)=>unitDimension(o)==unitDimension(selected['yield_unit']!)).toList();
      if(compatible.isNotEmpty)return compatible;
    }
    return options;
  }
  Widget buildField(FormFieldSpec f,StateSetter setD) {
    if(f.options!=null) {
      final options=optionsFor(f);
      var value=selected[f.key];
      if(value==null||!options.contains(value))value=options.isEmpty?null:options.first;
      if(value!=null)selected[f.key]=value;
      return DropdownButtonFormField<String>(
        key:ValueKey('${f.key}:$value:${options.join(",")}'),value:value,
        decoration:InputDecoration(labelText:f.label),
        items:options.map((o)=>DropdownMenuItem(value:o,child:Text(o))).toList(),
        onChanged:f.readOnly?null:(v){if(v==null)return;setD((){
          selected[f.key]=v;controllers[f.key]!.text=v;
          if(f.key=='yield_unit'&&selected.containsKey('sale_unit')) {
            final all=fields.firstWhere((x)=>x.key=='sale_unit').options??const <String>[];
            final compatible=all.where((o)=>unitDimension(o)==unitDimension(v)).toList();
            if(compatible.isNotEmpty&&!compatible.contains(selected['sale_unit'])) {
              selected['sale_unit']=compatible.first;controllers['sale_unit']!.text=compatible.first;
            }
          }
        });},
        validator:f.required?(v)=>(v==null||v.isEmpty)?'Campo obligatorio':null:null,
      );
    }
    return TextFormField(controller:controllers[f.key],readOnly:f.readOnly,
      keyboardType:f.numeric?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,
      inputFormatters:f.numeric?[NumericThousandsFormatter()]:null,
      decoration:InputDecoration(labelText:f.label),
      validator:f.required?(v)=>(v==null||v.trim().isEmpty)?'Campo obligatorio':(f.numeric&&number(v)<=0&&f.key!='minutes'?'Ingresá un valor mayor que cero':null):null);
  }
  List<Widget> buildFields(StateSetter setD) {
    final widgets=<Widget>[];
    for(var i=0;i<fields.length;i++) {
      final f=fields[i];
      final companionKey=f.key=='qty'?'unit':(f.key.endsWith('_qty')?'${f.key.substring(0,f.key.length-4)}_unit':null);
      if(companionKey!=null&&i+1<fields.length&&fields[i+1].key==companionKey) {
        widgets.add(Padding(padding:const EdgeInsets.only(bottom:12),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(flex:3,child:buildField(f,setD)),const SizedBox(width:12),Expanded(flex:2,child:buildField(fields[i+1],setD))])));
        i++;
      } else {widgets.add(Padding(padding:const EdgeInsets.only(bottom:12),child:buildField(f,setD)));}
    }
    return widgets;
  }
  await showDialog<void>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
    title:Text(confirmingDelete?'¿Eliminar esta receta?':title),
    content:confirmingDelete?const Text('Esta acción no se puede deshacer. Se eliminarán también los ingredientes asociados y el historial de precios.'):SizedBox(width:400,child:SingleChildScrollView(child:Form(key:formKey,child:Column(mainAxisSize:MainAxisSize.min,children:buildFields(setD))))),
    actions:confirmingDelete?[
      TextButton(onPressed:()=>setD(()=>confirmingDelete=false),child:const Text('Volver')),
      FilledButton(style:FilledButton.styleFrom(backgroundColor:Theme.of(ctx).colorScheme.error),onPressed:()async{if(onDelete!=null)await onDelete();if(ctx.mounted)Navigator.of(ctx).pop();},child:const Text('Sí, eliminar')),
    ]:[
      if(onDelete!=null)TextButton.icon(style:TextButton.styleFrom(foregroundColor:Theme.of(ctx).colorScheme.error),onPressed:()=>setD(()=>confirmingDelete=true),icon:const Icon(Icons.delete_outline),label:const Text('Eliminar receta')),
      TextButton(onPressed:()=>Navigator.of(ctx).pop(),child:const Text('Cancelar')),
      FilledButton(onPressed:()async{
        if(!formKey.currentState!.validate())return;
        final values=<String,String>{};
        for(final f in fields) {
          if(f.options!=null) {
            final opts=optionsFor(f);
            final chosen=selected[f.key];
            values[f.key]=(chosen!=null&&opts.contains(chosen))?chosen:(opts.isNotEmpty?opts.first:'');
          } else {
            values[f.key]=controllers[f.key]!.text.trim();
          }
        }
        if(selected.containsKey('yield_unit')&&selected.containsKey('sale_unit')&&unitDimension(values['yield_unit']!)!=unitDimension(values['sale_unit']!)){ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('El rendimiento y la presentación de venta deben usar unidades compatibles.')));return;}
        await onSave(values);
        if(ctx.mounted)Navigator.of(ctx).pop();
      },child:const Text('Guardar')),
    ],
  )));
  for(final c in controllers.values)c.dispose();
}

class FormFieldSpec {
  final String key,label,initial;
  final bool numeric,required,readOnly;
  final List<String>? options;
  const FormFieldSpec(this.key,this.label,{this.initial='',this.numeric=false,this.required=true,this.readOnly=false,this.options});
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
      await Store.instance.db.insert('ingredient_prices',{'ingredient_id':id,'price':baseUnitPrice(price,number(v['qty']),v['unit']!),'date':now});
      if(mounted)setState((){});widget.onChange();
    });
  }
  Future<void> editIngredient(Map<String,Object?> item) async {
    await editDialog(context,'Editar insumo',[
      FormFieldSpec('name','Nombre',initial:item['name'] as String),
      FormFieldSpec('description','Descripción',initial:item['description'] as String,required:false),
      FormFieldSpec('qty','Cantidad de la presentación',initial:fmt(item['qty'] as num),numeric:true),
      FormFieldSpec('unit','Unidad',initial:item['unit'] as String,options:['g','kg','l','ml','cc','unidad']),
      FormFieldSpec('price','Precio actual',initial:fmt(item['price'] as num),numeric:true),
    ],(v)async{
      final normalized=titleCase(v['name']??'');
      final dup=await Store.instance.db.query('ingredients',where:'LOWER(name)=? AND id<>?',whereArgs:[normalized.toLowerCase(),item['id']],limit:1);
      if(dup.isNotEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ya existe un insumo con ese nombre.')));return;}
      final now=stamp();
      final price=number(v['price']);
      final oldPrice=(item['price'] as num).toDouble();
      final oldBasePrice=baseUnitPrice(oldPrice,item['qty'] as num,item['unit'] as String);
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
      // El historial guarda siempre el precio por unidad base; registrar cambios de precio o presentación.
      final newBasePrice=baseUnitPrice(price,qty,v['unit']!);
      if(newBasePrice!=oldBasePrice){
        await Store.instance.db.insert('ingredient_prices',{'ingredient_id':item['id'],'price':newBasePrice,'date':now});
      }
      if(mounted)setState((){});
      widget.onChange();
    });
  }
  Future<void> priceUpdate(Map<String,Object?> item) async {
    await editDialog(context,'Actualizar precio',const [FormFieldSpec('price','Nuevo precio',numeric:true)],(v)async{
      final price=number(v['price']);final now=stamp();
      await Store.instance.db.update('ingredients',{'price':price,'updated':now},where:'id=?',whereArgs:[item['id']]);
      await Store.instance.db.insert('ingredient_prices',{'ingredient_id':item['id'],'price':baseUnitPrice(price,item['qty'] as num,item['unit'] as String),'date':now});
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
      Text('Precio por ${baseUnitLabel(item['unit'] as String)}: '+cash(baseUnitPrice(item['price'] as num,item['qty'] as num,item['unit'] as String))),
      Text('Última actualización: '+dateLabel(item['updated'] as String)),
      const Divider(),const Text('Recetas que lo usan',style:TextStyle(fontWeight:FontWeight.bold)),
      if(recipes.isEmpty)const Text('Ninguna por ahora.'),...recipes.map((r)=>Text('• '+(r['name'] as String))),
    ]))), actions: [
      TextButton.icon(onPressed:() async {
        Navigator.pop(ctx);
        await showDialog<void>(context:context,builder:(h)=>AlertDialog(
          title:Text('Historial de precios · ${item['name']}'),
          content:SizedBox(width:320,child:history.isEmpty?const Text('Sin historial registrado.'):ListView(shrinkWrap:true,children:history.map((x)=>ListTile(title:Text('${cash(x['price'] as num)} por ${baseUnitLabel(item['unit'] as String)}'),subtitle:Text(dateLabel(x['date'] as String)))).toList())),
          actions:[TextButton(onPressed:()=>Navigator.pop(h),child:const Text('Cerrar'))],
        ));
        if(mounted)await detail(item);
      },icon:const Icon(Icons.history),label:const Text('Ver historial')),
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
      FilledButton.icon(onPressed:(){Navigator.pop(ctx);editIngredient(item);},icon:const Icon(Icons.edit),label:const Text('Actualizar información'))
    ]));
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
      FormFieldSpec('name','Nombre',initial:query.trim()),const FormFieldSpec('description','Descripción',required:false),const FormFieldSpec('minutes','Tiempo de preparación (min)',numeric:true),const FormFieldSpec('yield_qty','Cantidad que rinde',numeric:true),const FormFieldSpec('yield_unit','Unidad del rendimiento',options:['g','kg','ml','l','cc','unidad']),const FormFieldSpec('sale_qty','Presentación de venta',numeric:true),const FormFieldSpec('sale_unit','Unidad de presentación',options:['g','kg','ml','l','cc','unidad']),const FormFieldSpec('portions_per_presentation','Porciones por presentación',initial:'1',numeric:true),const FormFieldSpec('sale_price','Precio de venta',numeric:true),
    ],(v)async{final name=titleCase(v['name']??'');final dup=await Store.instance.db.query('recipes',where:'LOWER(name)=?',whereArgs:[name.toLowerCase()],limit:1);if(dup.isNotEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ya existe una receta con ese nombre.')));return;}if(unitDimension(v['yield_unit']!)!=unitDimension(v['sale_unit']!)){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('El rendimiento y la presentación de venta deben usar unidades compatibles.')));return;}final now=stamp();final price=number(v['sale_price']);final id=await Store.instance.db.insert('recipes',{'name':name,'description':v['description']??'','minutes':number(v['minutes']),'yield_qty':number(v['yield_qty']),'yield_unit':v['yield_unit'],'sale_qty':number(v['sale_qty']),'sale_unit':v['sale_unit'],'portions_per_presentation':number(v['portions_per_presentation'])>0?number(v['portions_per_presentation']):1,'sale_price':price,'updated':now,'sale_updated':now});await Store.instance.db.insert('recipe_prices',{'recipe_id':id,'price':price,'date':now});if(mounted)setState((){});widget.onChange();});
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
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Expanded(flex:3,child:TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),inputFormatters:[NumericThousandsFormatter()],decoration:const InputDecoration(labelText:'Cantidad usada'))),
          const SizedBox(width:12),
          Expanded(flex:2,child:DropdownButtonFormField<String>(
            value:unit,
            decoration:const InputDecoration(labelText:'Unidad'),
            items:const ['g','kg','ml','l','unidad'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
            onChanged:(v){if(v!=null)setD(()=>unit=v);},
          )),
        ]),
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
    final qty = TextEditingController(text:fmt(item['qty'] as num));
    String unit = item['unit'] as String;
    final searchController = TextEditingController(text:chosen['name'] as String);
    if (!mounted) return;
    await showDialog<void>(
      context:context,
      builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
        title:const Text('Editar ingrediente'),
        content:SizedBox(width:400, child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextFormField(
            initialValue:chosen!['name'] as String,
            readOnly:true,
            decoration:const InputDecoration(labelText:'Insumo',prefixIcon:Icon(Icons.lock_outline)),
          ),
          Align(alignment:Alignment.centerLeft,child:Text('Presentación: ${chosen!['qty']} ${chosen!['unit']} · envase: ${cash(chosen!['price'] as num)}')),
          const SizedBox(height:12),
          Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Expanded(flex:3,child:TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),inputFormatters:[NumericThousandsFormatter()],decoration:const InputDecoration(labelText:'Cantidad usada'))),
            const SizedBox(width:12),
            Expanded(flex:2,child:DropdownButtonFormField<String>(
              value:['g','kg','ml','l','unidad'].contains(unit)?unit:'g',
              decoration:const InputDecoration(labelText:'Unidad'),
              items:const ['g','kg','ml','l','unidad'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
              onChanged:(v){if(v!=null)setD(()=>unit=v);},
            )),
          ]),
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
    await editDialog(
      context,
      'Editar receta',
      [
        FormFieldSpec('name','Nombre',initial:r['name'] as String),
        FormFieldSpec('description','Descripción',initial:r['description'] as String,required:false),
        FormFieldSpec('minutes','Tiempo de preparación (min)',initial:fmt(r['minutes'] as num),numeric:true),
        FormFieldSpec('yield_qty','Cantidad que rinde',initial:fmt(r['yield_qty'] as num),numeric:true),
        FormFieldSpec('yield_unit','Unidad',initial:r['yield_unit'] as String,options:['g','kg','ml','l','cc','unidad']),
        FormFieldSpec('sale_qty','Presentación de venta',initial:fmt(r['sale_qty'] as num),numeric:true),
        FormFieldSpec('sale_unit','Unidad',initial:r['sale_unit'] as String,options:['g','kg','ml','l','cc','unidad']),
        FormFieldSpec('portions_per_presentation','Porciones por presentación',initial:fmt((r['portions_per_presentation'] as num?)??1),numeric:true),
        FormFieldSpec('sale_price','Precio de venta',initial:fmt(r['sale_price'] as num),numeric:true),
      ],
      (v) async {
        final name=titleCase(v['name']??'');
        final dup=await Store.instance.db.query('recipes',where:'LOWER(name)=? AND id<>?',whereArgs:[name.toLowerCase(),r['id']],limit:1);
        if(dup.isNotEmpty) {
          if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ya existe una receta con ese nombre.')));
          return;
        }
        if(unitDimension(v['yield_unit']!)!=unitDimension(v['sale_unit']!)) {
          if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('El rendimiento y la presentación de venta deben usar unidades compatibles.')));
          return;
        }
        final now=stamp();
        final price=number(v['sale_price']);
        await Store.instance.db.update('recipes',{
          'name':name,
          'description':v['description']??'',
          'minutes':number(v['minutes']),
          'yield_qty':number(v['yield_qty']),
          'yield_unit':v['yield_unit'],
          'sale_qty':number(v['sale_qty']),
          'sale_unit':v['sale_unit'],
          'portions_per_presentation':number(v['portions_per_presentation'])>0?number(v['portions_per_presentation']):1,
          'sale_price':price,
          'updated':now,
          'sale_updated':now,
        },where:'id=?',whereArgs:[r['id']]);
        if(price!=(r['sale_price'] as num).toDouble()) {
          await Store.instance.db.insert('recipe_prices',{'recipe_id':r['id'],'price':price,'date':now});
        }
        if(mounted)setState((){});
        widget.onChange();
      },
      onDelete:() async {
        await Store.instance.db.delete('recipe_items',where:'recipe_id=?',whereArgs:[r['id']]);
        await Store.instance.db.delete('recipe_prices',where:'recipe_id=?',whereArgs:[r['id']]);
        await Store.instance.db.delete('recipes',where:'id=?',whereArgs:[r['id']]);
        if(mounted){setState((){});ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Receta eliminada.')));}
        widget.onChange();
      },
    );
  }
  Future<void> editSale(Map<String,Object?> r) async {
    await editDialog(context,'Precio y presentación',[
      FormFieldSpec('qty','Cantidad de venta',initial:fmt(r['sale_qty'] as num),numeric:true),
      FormFieldSpec('unit','Unidad de venta',initial:r['sale_unit'] as String),
      FormFieldSpec('price','Precio de venta',initial:fmt(r['sale_price'] as num),numeric:true),
    ],(v)async{await Store.instance.db.update('recipes',{'sale_qty':number(v['qty']),'sale_unit':v['unit'],'sale_price':number(v['price']),'sale_updated':stamp()},where:'id=?',whereArgs:[r['id']]);if(mounted)setState((){});widget.onChange();});
  }
  Future<void> reopenRecipe(Map<String,Object?> r) async {
    if (!mounted) return;
    final rows = await Store.instance.db.query('recipes', where:'id=?', whereArgs:[r['id']], limit:1);
    if (!mounted || rows.isEmpty) return;
    await detail(rows.first);
  }

  Future<void> detail(Map<String,Object?> r) async {
    final items=await Store.instance.db.rawQuery('SELECT ri.id,ri.recipe_id,ri.ingredient_id,ri.qty,ri.unit,i.name,i.price,i.qty AS pack_qty,i.unit AS pack_unit FROM recipe_items ri JOIN ingredients i ON i.id=ri.ingredient_id WHERE ri.recipe_id=?',[r['id']]);
    final saleHistory=await Store.instance.db.query('recipe_prices',where:'recipe_id=?',whereArgs:[r['id']],orderBy:'date DESC');
    final c=await cost(r);final sale=(r['sale_price'] as num).toDouble();final settings=await Store.instance.db.query('settings',where:'key=?',whereArgs:['ideal_margin'],limit:1);final ideal=settings.isEmpty?60.0:number(settings.first['value'] as String);final yieldInfo=unitInfo(r['yield_unit'] as String);final saleInfo=unitInfo(r['sale_unit'] as String);final compatible=yieldInfo.dimension==saleInfo.dimension;final saleCost=compatible&&(yieldInfo.factor*(r['yield_qty'] as num).toDouble()>0)?c*((r['sale_qty'] as num).toDouble()*saleInfo.factor/((r['yield_qty'] as num).toDouble()*yieldInfo.factor)):double.nan;final margin=sale>0?(sale-saleCost)/sale*100:0;
    if(!mounted)return;
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:Row(children:[
        Expanded(child:Text(r['name'] as String, maxLines:2, overflow:TextOverflow.ellipsis)),
        IconButton(
          tooltip:'Editar receta',
          icon:const Icon(Icons.edit_outlined),
          onPressed:() async {
            Navigator.pop(ctx);
            await editRecipe(r);
            if(mounted) await reopenRecipe(r);
          },
        ),
        IconButton(
          tooltip:'Cerrar',
          icon:const Icon(Icons.close),
          onPressed:()=>Navigator.pop(ctx),
        ),
      ]),
      content:SizedBox(width:400,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
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
          trailing:IconButton(icon:const Icon(Icons.edit_outlined),tooltip:'Editar ingrediente',onPressed:()async{Navigator.pop(ctx);await editIngredientItem(r,x);if(mounted)await reopenRecipe(r);}),
        );
      }),
    ]))),
      actions:[
        Wrap(
          alignment:WrapAlignment.end,
          spacing:8,
          children:[
            TextButton.icon(
              onPressed:() async {
                Navigator.pop(ctx);
                if(!mounted)return;
                await showDialog<void>(context:context,builder:(h)=>AlertDialog(
                  title:Text('Historial de venta · ${r['name']}'),
                  content:SizedBox(width:320,child:saleHistory.isEmpty?const Text('Sin historial registrado.'):ListView(shrinkWrap:true,children:saleHistory.map((x)=>ListTile(title:Text(cash(x['price'] as num)),subtitle:Text(dateLabel(x['date'] as String)))).toList())),
                  actions:[TextButton(onPressed:()=>Navigator.pop(h),child:const Text('Cerrar'))],
                ));
                if(mounted)await reopenRecipe(r);
              },
              icon:const Icon(Icons.history),
              label:const Text('Ver historial'),
            ),
            FilledButton.icon(
              onPressed:() async {
                Navigator.pop(ctx);
                await addIngredient(r);
                if(mounted)await reopenRecipe(r);
              },
              icon:const Icon(Icons.add),
              label:const Text('Agregar ingrediente'),
            ),
          ],
        ),
      ],
    ));
  }
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:TextField(controller:searchController,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar o registrar receta',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>query=v))),
    Expanded(child:FutureBuilder<List<Map<String,Object?>>>(future:data,builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final list=s.data!.where((r)=>(r['name'] as String).toLowerCase().contains(query.toLowerCase())).toList();final exact=list.any((r)=>(r['name'] as String).toLowerCase()==query.trim().toLowerCase());final canCreate=query.trim().isNotEmpty&&!exact;if(list.isEmpty&&!canCreate)return const Center(child:Text('Buscá una receta por su nombre.'));return ListView(children:[if(canCreate)Card(child:ListTile(leading:const Icon(Icons.add_circle_outline),title:Text('Registrar ${titleCase(query)}'),subtitle:const Text('Crear una receta nueva'),onTap:add)),...list.map((r)=>FutureBuilder<int>(future:Store.instance.db.query('recipe_items',where:'recipe_id=?',whereArgs:[r['id']]).then((x)=>x.length),builder:(c,count)=>Card(child:ListTile(title:Text(r['name'] as String),subtitle:(count.data??0)==0?const Text('⚠ Agregá ingredientes para calcular el costo',style:TextStyle(color:Colors.orange)):FutureBuilder<double>(future:cost(r),builder:(c,cs){final yi=unitInfo(r['yield_unit'] as String);final si=unitInfo(r['sale_unit'] as String);final y=(r['yield_qty'] as num).toDouble();final compatible=yi.dimension==si.dimension&&y>0;final cst=cs.hasData&&compatible?cs.data!*(r['sale_qty'] as num).toDouble()*si.factor/(y*yi.factor):double.nan;return Text('Costo por presentación: ${cst.isFinite?cash(cst):'No disponible'} · Venta: ${cash(r['sale_price'] as num)}');}),trailing:const Icon(Icons.chevron_right),onTap:()=>detail(r))))) ]); })),
  ]);
  @override void dispose(){searchController.dispose();super.dispose();}
}



class PresupuestoPage extends StatefulWidget {
  const PresupuestoPage({super.key});
  @override State<PresupuestoPage> createState() => _PresupuestoPageState();
}

class _PresupuestoPageState extends State<PresupuestoPage> {
  final searchController = TextEditingController();
  final portionsController = TextEditingController();
  String query = '';
  Map<String,Object?>? selected;

  ({String dimension, double factor}) unitInfo(String raw) {
    final u = raw.trim().toLowerCase().replaceAll(' ', '');
    switch (u) {
      case 'kg': case 'kilo': case 'kilos': case 'kilogramo': case 'kilogramos':
        return (dimension:'mass',factor:1000);
      case 'g': case 'gr': case 'gramo': case 'gramos':
        return (dimension:'mass',factor:1);
      case 'l': case 'lt': case 'lts': case 'litro': case 'litros':
        return (dimension:'volume',factor:1000);
      case 'ml': case 'cc': case 'mililitro': case 'mililitros':
        return (dimension:'volume',factor:1);
      case 'unidad': case 'unidades': case 'u': case 'unid':
        return (dimension:'count',factor:1);
      default:
        return (dimension:'other:' + u,factor:1);
    }
  }

  Future<({double batchCost, double margin})> metrics(Map<String,Object?> recipe) async {
    final rows = await Store.instance.db.rawQuery(
      'SELECT ri.qty,ri.unit,i.price,i.qty AS pack_qty,i.unit AS pack_unit FROM recipe_items ri JOIN ingredients i ON i.id=ri.ingredient_id WHERE ri.recipe_id=?',
      [recipe['id']],
    );
    double total = 0;
    for (final x in rows) {
      final used = unitInfo(x['unit'] as String);
      final pack = unitInfo(x['pack_unit'] as String);
      if (used.dimension != pack.dimension) {
        throw StateError('Hay unidades incompatibles en los ingredientes de esta receta.');
      }
      final packBase = (x['pack_qty'] as num).toDouble() * pack.factor;
      if (packBase > 0) {
        total += ((x['price'] as num).toDouble() / packBase) *
            ((x['qty'] as num).toDouble() * used.factor);
      }
    }
    final rates = await Store.instance.db.query('settings', where:'key=?', whereArgs:['hourly_rate'], limit:1);
    final hourlyRate = rates.isEmpty ? 0.0 : number(rates.first['value'] as String);
    total += ((recipe['minutes'] as num).toDouble() / 60) * hourlyRate;
    final margins = await Store.instance.db.query('settings', where:'key=?', whereArgs:['ideal_margin'], limit:1);
    final margin = margins.isEmpty ? 60.0 : number(margins.first['value'] as String);
    return (batchCost:total, margin:margin);
  }

  void clearSelection() {
    setState(() {
      selected = null;
      query = '';
      searchController.clear();
      portionsController.clear();
    });
  }

  @override Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String,Object?>>>(
      future: Store.instance.db.query('recipes', orderBy:'name COLLATE NOCASE'),
      builder:(context,snapshot) {
        if (!snapshot.hasData) return const Center(child:CircularProgressIndicator());
        final recipes = snapshot.data!;
        final matches = query.trim().isEmpty
            ? <Map<String,Object?>>[]
            : recipes.where((r)=>(r['name'] as String).toLowerCase().contains(query.trim().toLowerCase())).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Presupuesto', style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:Color(0xFF17365D))),
            const SizedBox(height:6),
            const Text('Consultá el costo de una receta y calculá el precio sugerido para otra presentación.'),
            const SizedBox(height:16),
            TextField(
              controller:searchController,
              decoration:InputDecoration(
                labelText:'Buscar receta',
                hintText:'Escribí el nombre de una receta',
                prefixIcon:const Icon(Icons.search,color:Color(0xFF245B86)),
                suffixIcon:searchController.text.isEmpty?null:IconButton(icon:const Icon(Icons.close),onPressed:clearSelection),
                border:const OutlineInputBorder(),
              ),
              onChanged:(v)=>setState(() {
                query=v;
                if(selected!=null && v.trim().toLowerCase()!=(selected!['name'] as String).toLowerCase()) {
                  selected=null;
                  portionsController.clear();
                }
              }),
            ),
            if (selected == null && query.trim().isNotEmpty) ...[
              const SizedBox(height:8),
              if(matches.isEmpty) const Padding(padding:EdgeInsets.all(12),child:Text('No se encontraron recetas con ese nombre.')),
              ...matches.map((r)=>Card(
                child:ListTile(
                  leading:const Icon(Icons.menu_book_outlined,color:Color(0xFF245B86)),
                  title:Text(r['name'] as String),
                  subtitle:Text((r['description'] as String).isEmpty?'Sin descripción':r['description'] as String,maxLines:2,overflow:TextOverflow.ellipsis),
                  trailing:const Icon(Icons.chevron_right),
                  onTap:()=>setState(() {
                    selected=r;
                    query=r['name'] as String;
                    searchController.text=query;
                    portionsController.clear();
                  }),
                ),
              )),
            ],
            if (selected != null) ...[
              const SizedBox(height:12),
              FutureBuilder<({double batchCost, double margin})>(
                future:metrics(selected!),
                builder:(context,calc) {
                  if(calc.hasError) return Card(child:Padding(padding:const EdgeInsets.all(16),child:Text('No se pudo calcular esta receta: ${calc.error}')));
                  if(!calc.hasData) return const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()));
                  final r=selected!;
                  final m=calc.data!;
                  final yieldQty=(r['yield_qty'] as num).toDouble();
                  final yieldInfo=unitInfo(r['yield_unit'] as String);
                  final saleInfo=unitInfo(r['sale_unit'] as String);
                  final saleQty=(r['sale_qty'] as num).toDouble();
                  final compatible=yieldInfo.dimension==saleInfo.dimension && yieldQty>0;
                  final currentCost=compatible ? m.batchCost * saleQty * saleInfo.factor / (yieldQty * yieldInfo.factor) : double.nan;
                  final currentPortions=((r['portions_per_presentation'] as num?)??1).toDouble();
                  final newQty=number(portionsController.text);
                  final currentPresentationCost=compatible ? m.batchCost * saleQty * saleInfo.factor / (yieldQty * yieldInfo.factor) : double.nan;
                  final newCost=compatible && currentPortions>0 && newQty>0 ? currentPresentationCost * newQty / currentPortions : double.nan;
                  final canSuggest=newCost.isFinite && m.margin<100 && m.margin>=0;
                  final suggested=canSuggest ? newCost/(1-m.margin/100) : double.nan;
                  return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                    Card(
                      child:Padding(
                        padding:const EdgeInsets.all(18),
                        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                          Row(children:[
                            const Expanded(child:Text('RECETA SELECCIONADA',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold,letterSpacing:1,color:Color(0xFF245B86)))),
                            IconButton(tooltip:'Elegir otra receta',onPressed:clearSelection,icon:const Icon(Icons.close)),
                          ]),
                          Text(r['name'] as String,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Color(0xFF17365D))),
                          const SizedBox(height:6),
                          Text((r['description'] as String).isEmpty?'Sin descripción':r['description'] as String),
                          const Divider(height:24),
                          _budgetInfo('Presentación actual','${fmt(saleQty)} ${r['sale_unit']}'),
                          _budgetInfo('Porciones por presentación',fmt(currentPortions)),
                          _budgetInfo('Costo por presentación',compatible?cash(currentCost):'Unidades incompatibles'),
                          _budgetInfo('Precio de venta actual',cash(r['sale_price'] as num)),
                        ]),
                      ),
                    ),
                    Card(
                      child:Padding(
                        padding:const EdgeInsets.all(18),
                        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                          const Text('Calcular otra presentación',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:Color(0xFF17365D))),
                          const SizedBox(height:6),
                          Text('Ingresá la cantidad de porciones que necesitás. El cálculo usa ${fmt(currentPortions)} porciones por presentación y el margen ideal de ${fmt(m.margin)}%.'),
                          const SizedBox(height:12),
                          TextField(
                            controller:portionsController,
                            keyboardType:const TextInputType.numberWithOptions(decimal:true),
                            inputFormatters:[NumericThousandsFormatter()],
                            decoration:const InputDecoration(labelText:'Cantidad de porciones',hintText:'Ej. 12',prefixIcon:Icon(Icons.pie_chart_outline,color:Color(0xFF245B86)),border:OutlineInputBorder()),
                            onChanged:(_)=>setState((){}),
                          ),
                          if(newQty>0 && compatible) ...[
                            const SizedBox(height:18),
                            Container(
                              padding:const EdgeInsets.all(16),
                              decoration:BoxDecoration(color:const Color(0xFFE7EEF7),borderRadius:BorderRadius.circular(12)),
                              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                                const Text('RESULTADO DEL PRESUPUESTO',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold,letterSpacing:1,color:Color(0xFF245B86))),
                                const SizedBox(height:10),
                                _budgetInfo('Porciones presupuestadas',fmt(newQty)),
                                _budgetInfo('Costo estimado',cash(newCost)),
                                const Divider(),
                                Text('Precio de venta sugerido',style:TextStyle(color:Color(0xFF17365D),fontWeight:FontWeight.w600)),
                                const SizedBox(height:4),
                                Text(canSuggest?cash(suggested):'No disponible',style:const TextStyle(fontSize:28,fontWeight:FontWeight.bold,color:Color(0xFF17365D))),
                                if(!canSuggest) const Text('Revisá el margen ideal en Parámetros: debe ser igual o mayor que 0% y menor que 100%.'),
                              ]),
                            ),
                          ],
                          if(!compatible) const Padding(padding:EdgeInsets.only(top:10),child:Text('No se puede calcular porque el rendimiento y la presentación de venta usan unidades incompatibles.',style:TextStyle(color:Colors.red))),
                        ]),
                      ),
                    ),
                  ]);
                },
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _budgetInfo(String label,String value) => Padding(
    padding:const EdgeInsets.symmetric(vertical:5),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Expanded(child:Text(label,style:const TextStyle(color:Color(0xFF5D6B7A)))),
      const SizedBox(width:12),
      Flexible(child:Text(value,textAlign:TextAlign.end,style:const TextStyle(fontWeight:FontWeight.w600))),
    ]),
  );

  @override void dispose() {
    searchController.dispose();
    portionsController.dispose();
    super.dispose();
  }
}

class DataTransferService {
  static const tableColumns = <String, List<String>>{
    'ingredients': ['id','name','description','qty','unit','price','updated'],
    'ingredient_prices': ['id','ingredient_id','price','date'],
    'recipes': ['id','name','description','minutes','yield_qty','yield_unit','sale_qty','sale_unit','portions_per_presentation','sale_price','updated','sale_updated'],
    'recipe_items': ['id','recipe_id','ingredient_id','qty','unit'],
    'recipe_prices': ['id','recipe_id','price','date'],
    'settings': ['key','value'],
  };
  static const importOrder = ['ingredients','recipes','ingredient_prices','recipe_prices','recipe_items','settings'];
  static const deleteOrder = ['recipe_items','ingredient_prices','recipe_prices','ingredients','recipes','settings'];

  static CellValue? toCellValue(Object? value) {
    if (value == null) return TextCellValue('');
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    if (value is bool) return BoolCellValue(value);
    return TextCellValue(value.toString());
  }

  static Future<File> exportWorkbook() async {
    final workbook = Excel.createExcel();
    for (final table in tableColumns.keys) {
      final sheet = workbook[table];
      sheet.appendRow(tableColumns[table]!.map((c) => TextCellValue(c)).toList());
      final rows = await Store.instance.db.query(table, orderBy: table == 'settings' ? 'key' : 'id');
      for (final row in rows) {
        sheet.appendRow(tableColumns[table]!.map((column) => toCellValue(row[column])).toList());
      }
    }
    if (workbook.tables.containsKey('Sheet1')) workbook.delete('Sheet1');
    final bytes = workbook.save();
    if (bytes == null) throw Exception('No se pudo generar el archivo Excel.');
    final directory = await getTemporaryDirectory();
    final file = File(path.join(directory.path, 'costeapp_respaldo.xlsx'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.toString();
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is BoolCellValue) return value.value.toString();
    if (value is DateCellValue) return value.asDateTimeLocal().toIso8601String();
    if (value is DateTimeCellValue) return value.asDateTimeLocal().toIso8601String();
    if (value is FormulaCellValue) return value.formula;
    return value.toString();
  }

  static Object? parseValue(String table, String column, String raw) {
    if (raw.trim().isEmpty) return null;
    const integerColumns = {'id','ingredient_id','recipe_id'};
    const numericColumns = {'qty','price','minutes','yield_qty','sale_qty','portions_per_presentation','sale_price'};
    if (integerColumns.contains(column)) {
      final value = num.tryParse(raw.trim());
      if (value == null) throw FormatException('El valor "$raw" no es válido para $column.');
      return value.toInt();
    }
    if (numericColumns.contains(column)) {
      final value = double.tryParse(raw.trim().replaceAll(' ', '').replaceAll(',', '.'));
      if (value == null) throw FormatException('El valor "$raw" no es válido para $column.');
      return value;
    }
    return raw;
  }

  static Future<Map<String, List<Map<String, Object?>>>> readWorkbook(List<int> bytes) async {
    final workbook = Excel.decodeBytes(bytes);
    final parsed = <String, List<Map<String, Object?>>>{};
    for (final entry in tableColumns.entries) {
      final table = entry.key;
      final columns = entry.value;
      final sheet = workbook.tables[table];
      if (sheet == null || sheet.rows.isEmpty) throw FormatException('Falta la hoja "$table" o está vacía.');
      final headers = sheet.rows.first.map((cell) => cellText(cell).trim()).toList();
      for (final required in columns) {
        if (required == 'portions_per_presentation' && table == 'recipes') continue;
        if (!headers.contains(required)) throw FormatException('La hoja "$table" no contiene la columna "$required".');
      }
      final rows = <Map<String, Object?>>[];
      for (final cells in sheet.rows.skip(1)) {
        if (cells.every((cell) => cellText(cell).trim().isEmpty)) continue;
        final row = <String, Object?>{};
        for (final column in columns) {
          final index = headers.indexOf(column);
          if (index < 0 && table == 'recipes' && column == 'portions_per_presentation') { row[column] = 1.0; continue; }
          final raw = index < cells.length ? cellText(cells[index]) : '';
          final value = parseValue(table, column, raw);
          if (value != null) row[column] = value;
        }
        if (table == 'recipes' && ((row['portions_per_presentation'] as num?)?.toDouble() ?? 0) <= 0) row['portions_per_presentation'] = 1.0;
        rows.add(row);
      }
      parsed[table] = rows;
    }
    final ingredientIds = parsed['ingredients']!.map((r) => r['id']).whereType<int>().toSet();
    final recipeIds = parsed['recipes']!.map((r) => r['id']).whereType<int>().toSet();
    for (final row in parsed['recipe_items']!) {
      if (!ingredientIds.contains(row['ingredient_id']) || !recipeIds.contains(row['recipe_id'])) {
        throw FormatException('Hay un ingrediente de receta que no coincide con los insumos o recetas del archivo.');
      }
    }
    for (final row in parsed['ingredient_prices']!) {
      if (!ingredientIds.contains(row['ingredient_id'])) throw FormatException('El historial de precios hace referencia a un insumo inexistente.');
    }
    for (final row in parsed['recipe_prices']!) {
      if (!recipeIds.contains(row['recipe_id'])) throw FormatException('El historial de venta hace referencia a una receta inexistente.');
    }
    return parsed;
  }

  static Future<void> importWorkbook(Map<String, List<Map<String, Object?>>> data) async {
    await Store.instance.db.transaction((txn) async {
      for (final table in deleteOrder) { await txn.delete(table); }
      for (final table in importOrder) {
        for (final row in data[table]!) {
          await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }
}

class SettingsPage extends StatefulWidget { final VoidCallback onDataChanged; const SettingsPage({super.key,required this.onDataChanged}); @override State<SettingsPage> createState()=>_SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage> {
  final rate=TextEditingController();final margin=TextEditingController();bool ready=false;
  String? lastRateUpdate;
  Future<void> load() async {
    lastRateUpdate=null;
    final rows=await Store.instance.db.query('settings');
    for(final r in rows){
      if(r['key']=='hourly_rate')rate.text=fmt(number(r['value'] as String));
      if(r['key']=='ideal_margin')margin.text=fmt(number(r['value'] as String));
      if(r['key']=='hourly_rate_updated')lastRateUpdate=r['value'] as String?;
    }
    if(mounted)setState(()=>ready=true);
  }
  @override void initState(){super.initState();load();}
  Future<void> save() async {
    final db=Store.instance.db;
    final savedRows=await db.query('settings',columns:['value'],where:'key=?',whereArgs:['hourly_rate'],limit:1);
    final savedRate=savedRows.isEmpty?null:savedRows.first['value'] as String?;
    final newRate=number(rate.text).toString();
    final dateRows=await db.query('settings',columns:['value'],where:'key=?',whereArgs:['hourly_rate_updated'],limit:1);
    final existingDate=dateRows.isEmpty?null:dateRows.first['value'] as String?;
    if(savedRate!=newRate || DateTime.tryParse(existingDate??'')==null) {
      final now=stamp();
      await db.insert('settings',{'key':'hourly_rate_updated','value':now},conflictAlgorithm:ConflictAlgorithm.replace);
      lastRateUpdate=now;
    }
    await db.update('settings',{'value':newRate},where:'key=?',whereArgs:['hourly_rate']);
    await db.update('settings',{'value':number(margin.text).toString()},where:'key=?',whereArgs:['ideal_margin']);
    if(mounted) {
      setState(() {});
      widget.onDataChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Parámetros guardados.')));
    }
  }
  Future<void> exportData() async {
    try {
      final file = await DataTransferService.exportWorkbook();
      await Share.shareXFiles([XFile(file.path)], text: 'Respaldo de Costeapp');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('No se pudo exportar el Excel: $e')));
    }
  }

  Future<void> importData() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null) throw Exception('No se pudo leer el archivo seleccionado.');
      final data = await DataTransferService.readWorkbook(bytes);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reemplazar los datos actuales'),
          content: Text('El archivo contiene ${data['ingredients']!.length} insumos y ${data['recipes']!.length} recetas. Se reemplazarán todos los datos actuales, incluidos los historiales y parámetros. Esta acción no se puede deshacer. ¿Querés continuar?'),
          actions: [
            TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
            FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Importar y reemplazar')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await DataTransferService.importWorkbook(data);
      await load();
      widget.onDataChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Datos importados correctamente.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('No se pudo importar el Excel: $e')));
    }
  }

  @override Widget build(BuildContext context)=>!ready?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(20),children:[
    const Text('Configurá los valores que se usan para estimar tus costos.'),
    const SizedBox(height:24),TextField(controller:rate,keyboardType:const TextInputType.numberWithOptions(decimal:true),inputFormatters:[NumericThousandsFormatter()],decoration:const InputDecoration(labelText:'Valor de la hora de trabajo',prefixText:'\$ ',helperText:'En pesos argentinos')),
    Padding(padding:const EdgeInsets.only(top:6),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Icon(Icons.calendar_month_outlined,size:18,color:Color(0xFF5D6B7A)),
      const SizedBox(width:8),
      Expanded(child:Text(lastRateUpdate==null?'Última actualización: sin registro':'Última actualización: ${dateLabel(lastRateUpdate!)}',style:const TextStyle(color:Color(0xFF5D6B7A)))),
    ])),
    const SizedBox(height:18),TextField(controller:margin,keyboardType:const TextInputType.numberWithOptions(decimal:true),inputFormatters:[NumericThousandsFormatter()],decoration:const InputDecoration(labelText:'Margen de contribución ideal',suffixText:'%',helperText:'Objetivo sobre el precio de venta')),
    const SizedBox(height:24),FilledButton.icon(onPressed:save,icon:const Icon(Icons.save_outlined),label:const Text('Guardar parámetros')),
    const SizedBox(height:28),
    const Text('Respaldo y migración',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),
    const Text('Exportá toda la información a un Excel para guardarla o transferirla a otro dispositivo. La importación reemplaza los datos que hay actualmente en este teléfono.'),
    const SizedBox(height:12),
    OutlinedButton.icon(onPressed:exportData,icon:const Icon(Icons.file_download_outlined),label:const Text('Exportar toda la información a Excel')),
    const SizedBox(height:8),
    OutlinedButton.icon(onPressed:importData,icon:const Icon(Icons.file_upload_outlined),label:const Text('Importar Excel de otro dispositivo')),
    const SizedBox(height:24),const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Margen de contribución = (precio de venta − costo estimado) ÷ precio de venta. El costo estimado incluye insumos y mano de obra.'))),
  ]);
  @override void dispose(){rate.dispose();margin.dispose();super.dispose();}
}
