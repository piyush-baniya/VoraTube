import 'package:flutter/material.dart';

import '../../../../shared/widgets/legal_document_view.dart';

/// In-app Privacy Policy for VoraTube.
///
/// Displays the contents of `assets/legal/privacy_policy.md` (kept in sync
/// with PRIVACY_POLICY.md at the repository root and the website) as flowing
/// document-style paragraphs.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: FutureBuilder<String>(
        future: DefaultAssetBundle.of(context)
            .loadString('assets/legal/privacy_policy.md'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return LegalDocumentView(markdown: snapshot.data!);
        },
      ),
    );
  }
}