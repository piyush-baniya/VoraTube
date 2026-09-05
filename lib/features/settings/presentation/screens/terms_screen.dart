import 'package:flutter/material.dart';

import '../../../../shared/widgets/legal_document_view.dart';

/// In-app Terms of Use for VoraTube.
///
/// Displays the contents of `assets/legal/terms_of_use.md` as flowing
/// document-style paragraphs, matching the Privacy Policy screen.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Use')),
      body: FutureBuilder<String>(
        future: DefaultAssetBundle.of(context)
            .loadString('assets/legal/terms_of_use.md'),
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