import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/network/api_exception.dart';
import 'admin_navigation.dart';
import 'admin_notification_campaign_page.dart';

/// Immutable operational trace: administrative audit actions and outgoing
/// notification / FCM records. It intentionally provides no delete or edit.
final class AdminActivityPage extends StatefulWidget {
  const AdminActivityPage({super.key});
  @override State<AdminActivityPage> createState() => _AdminActivityPageState();
}

final class _AdminActivityPageState extends State<AdminActivityPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late Future<List<Map<String, dynamic>>> _audit;
  late Future<List<Map<String, dynamic>>> _notifications;
  late Future<List<Map<String, dynamic>>> _merchantCampaigns;
  late Future<Map<String, dynamic>> _health;
  String _search = '';
  String _notificationCategory = '';
  String _deliveryStatus = '';
  @override void initState() { super.initState(); _tabs=TabController(length: 3,vsync:this); _reload(); }
  void _reload()=>setState(() { final api=AppScope.of(context); _health=api.loadAdminOperationalHealth(); _audit=api.loadAdminAuditLogs(); _notifications=api.loadAdminNotificationLogs(); _merchantCampaigns=api.loadAdminMerchantNotificationCampaigns(); });
  @override void dispose(){_tabs.dispose();super.dispose();}
  List<Map<String,dynamic>> _filter(List<Map<String,dynamic>> rows){final t=_search.trim().toLowerCase();return t.isEmpty?rows:rows.where((r)=>r.values.any((v)=>'$v'.toLowerCase().contains(t))).toList(growable:false);}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('سجل النشاط والإشعارات'),bottom:adminControlBottom(context,'activity'),actions:[IconButton(tooltip:'إرسال إشعار إداري',onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const AdminNotificationCampaignPage())),icon:const Icon(Icons.campaign_outlined)),IconButton(onPressed:_reload,icon:const Icon(Icons.refresh_rounded))]),body:Column(children:[_healthCard(),Padding(padding:const EdgeInsets.fromLTRB(16,14,16,5),child:TextField(onChanged:(v)=>setState(()=>_search=v),decoration:const InputDecoration(prefixIcon:Icon(Icons.search_rounded),hintText:'بحث بالفاعل أو الإجراء أو المرجع',border:OutlineInputBorder()))),TabBar(controller:_tabs,tabs:const [Tab(text:'سجل التدقيق'),Tab(text:'سجل الإشعارات'),Tab(text:'حملات التجار')]),Expanded(child:TabBarView(controller:_tabs,children:[_auditTab(),_notificationTab(),_merchantCampaignTab()]))]));
  Widget _healthCard() => FutureBuilder<Map<String, dynamic>>(
    future: _health,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: LinearProgressIndicator());
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: Card(child: ListTile(leading: Icon(Icons.monitor_heart_outlined), title: Text('تعذر قراءة حالة التشغيل حالياً.'))));
      }
      final health = snapshot.data!;
      final fcm = Map<String, dynamic>.from(health['fcm'] as Map? ?? const {});
      final dispatcher = Map<String, dynamic>.from(health['dispatcher'] as Map? ?? const {});
      final errors = Map<String, dynamic>.from(health['application_errors'] as Map? ?? const {});
      final alerts = (health['alerts'] as List? ?? const []).map((value) => '$value').toList(growable: false);
      final status = health['status'] as String? ?? 'warning';
      final healthy = status == 'ok';
      final dispatcherStatus = dispatcher['status'] as String? ?? 'unknown';
      String label(String value) => switch (value) {'ok' => 'سليم', 'warning' => 'تنبيه', 'stale' => 'متأخر', 'unknown' => 'غير متاح', _ => value};
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Card(
          color: healthy ? Theme.of(context).colorScheme.primaryContainer.withOpacity(.35) : Theme.of(context).colorScheme.errorContainer.withOpacity(.25),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(healthy ? Icons.monitor_heart_outlined : Icons.warning_amber_rounded, color: healthy ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error),
                const SizedBox(width: 9),
                Expanded(child: Text('حالة تشغيل المنصة: ${label(status)}', style: const TextStyle(fontWeight: FontWeight.w900))),
                TextButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('تحديث')),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(label: Text('قاعدة البيانات: سليمة')),
                Chip(label: Text('FCM: ${fcm['configured'] == true ? 'مهيأ' : 'غير مهيأ'}')),
                Chip(label: Text('أجهزة نشطة: ${fcm['active_devices'] ?? 0}')),
                Chip(label: Text('Cron: ${label(dispatcherStatus)}')),
                Chip(label: Text('إرسال 24س: ${fcm['sent_last_24h'] ?? 0}')),
                Chip(label: Text('فشل 24س: ${fcm['failed_last_24h'] ?? 0}')),
              ]),
              const SizedBox(height: 8),
              Text('آخر Cron: ${dispatcher['last_run_at'] ?? 'لم يُسجل بعد'} · أخطاء API خلال 24س: ${errors['count_last_24h'] ?? 0}', style: Theme.of(context).textTheme.bodySmall),
              if (errors['last_request_id'] != null) Text('آخر مرجع خطأ: ${errors['last_request_id']}', style: Theme.of(context).textTheme.bodySmall),
              if (alerts.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('تنبيهات: ${alerts.join('، ')}', style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
        ),
      );
    },
  );

  Widget _auditTab()=>FutureBuilder<List<Map<String,dynamic>>>(future:_audit,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return const Center(child:Text('تعذر تحميل سجل التدقيق.'));final rows=_filter(s.data??const []);if(rows.isEmpty)return const Center(child:Text('لا توجد عمليات مطابقة.'));return ListView.separated(padding:const EdgeInsets.fromLTRB(16,12,16,28),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,i){final r=rows[i];return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.history_rounded)),title:Text(r['action'] as String? ?? 'إجراء',style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('${r['actor_name']??'النظام'} · ${r['entity_type']??'—'}: ${r['entity_id']??'—'}\n${r['created_at']??''} · طلب ${r['request_id']??''}'),isThreeLine:true,onTap:()=>_details('تفاصيل سجل التدقيق',r)));});});
  Widget _notificationTab()=>FutureBuilder<List<Map<String,dynamic>>>(future:_notifications,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return const Center(child:Text('تعذر تحميل سجل الإشعارات.'));final base=_filter(s.data??const []);final rows=base.where((r)=>(_notificationCategory.isEmpty||r['category']==_notificationCategory)&&(_deliveryStatus.isEmpty||(_deliveryStatus=='failed'?(r['failed_count'] as num? ?? 0)>0:_deliveryStatus=='sent'?(r['sent_count'] as num? ?? 0)>0:(r['sent_count'] as num? ?? 0)==0&&(r['failed_count'] as num? ?? 0)==0))).toList(growable:false);return Column(children:[Padding(padding:const EdgeInsets.fromLTRB(16,12,16,6),child:Wrap(spacing:8,runSpacing:8,children:[SizedBox(width:168,child:DropdownButtonFormField<String>(value:_notificationCategory,isExpanded:true,decoration:const InputDecoration(labelText:'الفئة'),items:const [DropdownMenuItem(value:'',child:Text('كل الفئات')),DropdownMenuItem(value:'orders',child:Text('الطلبات')),DropdownMenuItem(value:'payments',child:Text('المدفوعات')),DropdownMenuItem(value:'delivery',child:Text('التوصيل')),DropdownMenuItem(value:'marketplace',child:Text('الحراج')),DropdownMenuItem(value:'store',child:Text('تحديثات المتاجر')),DropdownMenuItem(value:'support',child:Text('الدعم')),DropdownMenuItem(value:'wallet',child:Text('المحفظة')),DropdownMenuItem(value:'system',child:Text('النظام'))],onChanged:(v)=>setState(()=>_notificationCategory=v??''))),SizedBox(width:168,child:DropdownButtonFormField<String>(value:_deliveryStatus,isExpanded:true,decoration:const InputDecoration(labelText:'الإرسال'),items:const [DropdownMenuItem(value:'',child:Text('كل الحالات')),DropdownMenuItem(value:'sent',child:Text('تم الإرسال')),DropdownMenuItem(value:'failed',child:Text('فشل')),DropdownMenuItem(value:'pending',child:Text('معلّق'))],onChanged:(v)=>setState(()=>_deliveryStatus=v??'')))])),Expanded(child:rows.isEmpty?const Center(child:Text('لا توجد إشعارات مطابقة.')):ListView.separated(padding:const EdgeInsets.fromLTRB(16,6,16,28),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,i){final r=rows[i];final failed=(r['failed_count'] as num? ?? 0)>0;final sent=(r['sent_count'] as num? ?? 0)>0;return Card(child:ListTile(leading:CircleAvatar(child:Icon(failed?Icons.error_outline:sent?Icons.send_outlined:Icons.hourglass_empty_rounded)),title:Text(r['title'] as String? ?? 'إشعار',style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('${r['recipient_name']??'مستلم'} · ${r['category']??'—'}\n${r['body']??''}\n${failed?'فشل: ${r['latest_failure']??'—'}':sent?'تم الإرسال':'بانتظار الإرسال'}'),isThreeLine:true,onTap:()=>_details('تفاصيل الإشعار',r)));}))]);});
  String _merchantCampaignStatus(Map<String,dynamic> campaign)=>switch(campaign['campaign_status']){'approved'=>'نجحت الحملة','rejected'=>'مرفوضة',_=>'بانتظار المراجعة'};
  IconData _merchantCampaignIcon(Map<String,dynamic> campaign)=>switch(campaign['campaign_status']){'approved'=>Icons.check_circle_outline_rounded,'rejected'=>Icons.cancel_outlined,_=>Icons.hourglass_top_rounded};
  Future<void> _reviewMerchantCampaign(Map<String,dynamic> campaign) async {
    final pending=campaign['campaign_status']=='pending_review';
    final form=GlobalKey<FormState>(); final title=TextEditingController(text:(campaign['approved_title']??campaign['requested_title']??'') as String); final body=TextEditingController(text:(campaign['approved_body']??campaign['requested_body']??'') as String); final note=TextEditingController(text:campaign['review_note'] as String? ?? '');
    bool busy=false;
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(sheetContext)=>StatefulBuilder(builder:(sheetContext,modalSet){
      Future<void> decide(String decision) async { if(decision=='approve'&&!form.currentState!.validate())return; modalSet(()=>busy=true); try { final result=await AppScope.of(context).reviewMerchantNotificationCampaign(campaign['public_id'] as String,{'decision':decision,'title':title.text.trim(),'body':body.text.trim(),'review_note':note.text.trim()}); if(!sheetContext.mounted)return; Navigator.pop(sheetContext); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(result['campaign']?['campaign_status']=='approved'?'تمت الموافقة ووضع ${result['campaign']?['queued_notification_count']??0} إشعاراً في الطابور.':'تم رفض الحملة.'))); _reload(); } on ApiException catch(error) { if(sheetContext.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error.message))); } finally { if(sheetContext.mounted)modalSet(()=>busy=false); } }
      final finalTitle=(campaign['approved_title']??campaign['requested_title']??'حملة متجر') as String;
      return SafeArea(child:Padding(padding:EdgeInsets.fromLTRB(20,18,20,MediaQuery.viewInsetsOf(sheetContext).bottom+24),child:SingleChildScrollView(child:Form(key:form,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(pending?'مراجعة حملة تاجر':'بيانات حملة التاجر',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),const SizedBox(height:6),Text('${campaign['merchant_name']??'تاجر'} · ${campaign['store_name']??'متجر'} · المنتج: ${campaign['target_product_label']??'—'}'),const SizedBox(height:16),if(pending)...[TextFormField(controller:title,maxLength:180,decoration:const InputDecoration(labelText:'العنوان المعتمد'),validator:(v)=>(v??'').trim().length<2?'اكتب عنواناً صالحاً.':null),TextFormField(controller:body,minLines:3,maxLines:5,maxLength:1000,decoration:const InputDecoration(labelText:'النص المعتمد'),validator:(v)=>(v??'').trim().length<2?'اكتب نصاً صالحاً.':null),TextFormField(controller:note,minLines:2,maxLines:4,maxLength:1000,decoration:const InputDecoration(labelText:'ملاحظة القرار (اختيارية)')),const SizedBox(height:8),Text('جمهور الطلب: ${campaign['recipient_count_at_request']??0}. سيعاد حساب المتابعين والعملاء المؤهلين لحظة الموافقة.',style:Theme.of(context).textTheme.bodySmall),const SizedBox(height:16),Wrap(spacing:10,runSpacing:10,children:[FilledButton.icon(onPressed:busy?null:()=>decide('approve'),icon:const Icon(Icons.check_rounded),label:const Text('موافقة وإدراج في الطابور')),OutlinedButton.icon(onPressed:busy?null:()=>decide('reject'),icon:const Icon(Icons.close_rounded),label:const Text('رفض الحملة'))]) ] else ...[ListTile(contentPadding:EdgeInsets.zero,title:const Text('الحالة'),subtitle:Text(_merchantCampaignStatus(campaign))),ListTile(contentPadding:EdgeInsets.zero,title:const Text('النص المطلوب'),subtitle:Text('${campaign['requested_title']??''}\n${campaign['requested_body']??''}')),if(campaign['approved_title']!=null)ListTile(contentPadding:EdgeInsets.zero,title:const Text('النص المعتمد'),subtitle:Text('${campaign['approved_title']}\n${campaign['approved_body']??''}')),ListTile(contentPadding:EdgeInsets.zero,title:const Text('نتيجة الإرسال'),subtitle:Text('في الطابور: ${campaign['queued_notification_count']??0} · Push ناجح: ${campaign['recipients_with_sent_push']??0} · Push فاشل: ${campaign['recipients_with_failed_push']??0}')),if((campaign['review_note'] as String? ?? '').isNotEmpty)ListTile(contentPadding:EdgeInsets.zero,title:const Text('ملاحظة القرار'),subtitle:Text(campaign['review_note'] as String))]])))));
    }));
    title.dispose(); body.dispose(); note.dispose();
  }
  Widget _merchantCampaignTab()=>FutureBuilder<List<Map<String,dynamic>>>(future:_merchantCampaigns,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return const Center(child:Text('تعذر تحميل حملات التجار.'));final rows=_filter(s.data??const []);if(rows.isEmpty)return const Center(child:Text('لا توجد حملات تجار مطابقة.'));return ListView.separated(padding:const EdgeInsets.fromLTRB(16,12,16,28),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,i){final c=rows[i];final approved=c['campaign_status']=='approved';final rejected=c['campaign_status']=='rejected';final title=(c['approved_title']??c['requested_title']??'حملة متجر') as String;final result=approved?'تمت الموافقة · في الطابور: ${c['queued_notification_count']??0} · Push ناجح: ${c['recipients_with_sent_push']??0} · Push فاشل: ${c['recipients_with_failed_push']??0}':rejected?(c['review_note']??'لم تتم الموافقة على الحملة.'):'جمهور الطلب: ${c['recipient_count_at_request']??0} · بانتظار قرار الإدارة';return Card(child:ListTile(leading:CircleAvatar(child:Icon(_merchantCampaignIcon(c))),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('${c['merchant_name']??'تاجر'} · ${c['store_name']??'متجر'} · ${c['target_product_label']??'منتج'}\n$result'),isThreeLine:true,trailing:TextButton(onPressed:()=>_reviewMerchantCampaign(c),child:Text(c['campaign_status']=='pending_review'?'مراجعة':'التفاصيل'))));});});
  void _details(String title,Map<String,dynamic> r)=>showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(_)=>SafeArea(child:DraggableScrollableSheet(expand:false,initialChildSize:.68,maxChildSize:.92,builder:(_,scroll)=>ListView(controller:scroll,padding:const EdgeInsets.all(20),children:[Text(title,style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),...r.entries.where((e)=>e.value!=null).map((e)=>ListTile(title:Text(e.key),subtitle:SelectableText(e.value is Map||e.value is List?const JsonEncoder.withIndent('  ').convert(e.value):'${e.value}')))]))));
}
