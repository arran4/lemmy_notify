import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class ClickableLink extends StatelessWidget {
  final TextStyle linkStyle = const TextStyle(
    color: Colors.blue,
    decoration: TextDecoration.underline,
  );

  final String? linkUrlStr;
  final String? linkTitle;

  const ClickableLink({super.key, required this.linkUrlStr, required this.linkTitle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (linkUrlStr != null) {
          launchUrlString(linkUrlStr!);
        }
      },
      child: Text(
        '$linkTitle',
        style: linkStyle,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
