import 'package:flutter/material.dart';

import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/screen_header.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: 'Search'),
          Expanded(
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Search your library',
              message: 'Find songs, artists and albums.',
            ),
          ),
        ],
      ),
    );
  }
}
