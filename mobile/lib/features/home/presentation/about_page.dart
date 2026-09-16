import 'package:flutter/material.dart';

/// In-app equivalent of the public web "about" route.
final class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('عن تجارتي')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Icon(Icons.storefront_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 14),
      Text('تجارتي', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      const Text('منصة تجمع المتاجر المحلية والحراج وخدمات التوصيل في تجربة منظمة وآمنة.', textAlign: TextAlign.center, style: TextStyle(height: 1.7)),
      const SizedBox(height: 24),
      const _AboutPoint(icon: Icons.verified_user_outlined, title: 'إجراءات موثقة', body: 'الطلبات والدفع اليدوي والتوثيق والمراجعات تسير عبر حالات واضحة في الخادم.'),
      const _AboutPoint(icon: Icons.support_agent_outlined, title: 'دعم من داخل التطبيق', body: 'يمكنك فتح تذكرة ومتابعة الردود دون مغادرة التطبيق.'),
      const _AboutPoint(icon: Icons.privacy_tip_outlined, title: 'خصوصية البيانات', body: 'لا تُعرض الملفات الخاصة وسندات التحويل للزوار، ولا تضمّن التطبيق مفاتيح الخادم الإدارية.'),
    ]),
  );
}

final class _AboutPoint extends StatelessWidget {
  const _AboutPoint({required this.icon, required this.title, required this.body}); final IconData icon; final String title; final String body;
  @override Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(icon, color: Theme.of(context).colorScheme.primary), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text(body)));
}
