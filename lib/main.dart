import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const GitgramApp());
}

class GitgramApp extends StatelessWidget {
  const GitgramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gitgram',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF100D1C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B75FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF100D1C),
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class GitHubUser {
  final String login;
  final String name;
  final String bio;
  final String avatar;
  final String htmlUrl;
  final String location;
  final int publicRepos;
  final int followers;
  final int following;

  const GitHubUser({
    required this.login,
    required this.name,
    required this.bio,
    required this.avatar,
    required this.htmlUrl,
    required this.location,
    required this.publicRepos,
    required this.followers,
    required this.following,
  });

  factory GitHubUser.fromJson(Map<String, dynamic> json) {
    return GitHubUser(
      login: json['login']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      avatar: json['avatar_url']?.toString() ?? '',
      htmlUrl: json['html_url']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      publicRepos: json['public_repos'] as int? ?? 0,
      followers: json['followers'] as int? ?? 0,
      following: json['following'] as int? ?? 0,
    );
  }
}

class GitHubRepo {
  final String name;
  final String description;
  final String language;
  final int stars;
  final String url;

  const GitHubRepo({
    required this.name,
    required this.description,
    required this.language,
    required this.stars,
    required this.url,
  });

  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    return GitHubRepo(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      language: json['language']?.toString() ?? '',
      stars: json['stargazers_count'] as int? ?? 0,
      url: json['html_url']?.toString() ?? '',
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();

  GitHubUser? _user;
  List<GitHubRepo> _repos = [];
  List<String> _history = [];

  bool _loading = false;
  String? _error;

  static const Color purple = Color(0xFF9B75FF);
  static const Color cardColor = Color(0xFF1D1830);

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _history = prefs.getStringList('gitgram_history') ?? [];
    });
  }

  Future<void> _saveHistory(String username) async {
    final prefs = await SharedPreferences.getInstance();

    final updated = [
      username,
      ..._history.where((item) => item != username),
    ];

    final limited = updated.take(8).toList();

    await prefs.setStringList('gitgram_history', limited);

    if (mounted) {
      setState(() => _history = limited);
    }
  }

  Future<void> _searchUser([String? selected]) async {
    final username = (selected ?? _controller.text).trim();

    if (username.isEmpty) {
      setState(() {
        _error = 'Please enter a GitHub username.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _error = null;
      _user = null;
      _repos = [];
    });

    try {
      final uri = Uri.https(
        'api.github.com',
        '/users/$username',
      );

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github+json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 404) {
        throw Exception(
          'GitHub user "$username" was not found. Check the spelling.',
        );
      }

      if (response.statusCode == 403) {
        throw Exception(
          'GitHub API rate limit reached. Please wait and try again.',
        );
      }

      if (response.statusCode != 200) {
        throw Exception(
          'GitHub returned error ${response.statusCode}.',
        );
      }

      final userJson =
          jsonDecode(response.body) as Map<String, dynamic>;

      final user = GitHubUser.fromJson(userJson);

      final repoUri = Uri.https(
        'api.github.com',
        '/users/$username/repos',
        {
          'sort': 'updated',
          'per_page': '30',
        },
      );

      final repoResponse = await http.get(
        repoUri,
        headers: {
          'Accept': 'application/vnd.github+json',
        },
      ).timeout(const Duration(seconds: 15));

      List<GitHubRepo> repos = [];

      if (repoResponse.statusCode == 200) {
        final decoded = jsonDecode(repoResponse.body) as List<dynamic>;

        repos = decoded
            .whereType<Map<String, dynamic>>()
            .map(GitHubRepo.fromJson)
            .toList();
      }

      await _saveHistory(username);

      if (!mounted) return;

      setState(() {
        _user = user;
        _repos = repos;
        _controller.text = username;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openUrl(String value) async {
    if (value.isEmpty) return;

    final uri = Uri.tryParse(value);

    if (uri == null) return;

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open this link.'),
        ),
      );
    }
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('gitgram_history');

    if (mounted) {
      setState(() => _history = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: purple.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.code_rounded,
                color: purple,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'gitgram',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'GitHub',
            onPressed: () => _openUrl('https://github.com'),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              children: [
                const Text(
                  'Discover developers.',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Explore GitHub profiles and their work in one place.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 24),

                _searchBox(),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _errorBox(_error!),
                ],

                if (_loading) ...[
                  const SizedBox(height: 28),
                  const Center(
                    child: CircularProgressIndicator(
                      color: purple,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text('Finding developer...'),
                  ),
                ],

                if (_user != null) ...[
                  const SizedBox(height: 24),
                  _profileCard(_user!),
                  const SizedBox(height: 22),
                  _sectionTitle(
                    'Repositories',
                    '${_repos.length} shown',
                  ),
                  const SizedBox(height: 12),

                  if (_repos.isEmpty)
                    _emptyCard('No public repositories found.')
                  else
                    ..._repos.map(_repoCard),
                ],

                if (!_loading && _user == null && _history.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent searches',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: _clearHistory,
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _history.map((item) {
                      return ActionChip(
                        avatar: const Icon(
                          Icons.history,
                          size: 16,
                        ),
                        label: Text(item),
                        onPressed: () => _searchUser(item),
                        backgroundColor: cardColor,
                      );
                    }).toList(),
                  ),
                ],

                if (!_loading &&
                    _user == null &&
                    _history.isEmpty) ...[
                  const SizedBox(height: 42),
                  Icon(
                    Icons.travel_explore_rounded,
                    size: 66,
                    color: purple.withOpacity(0.75),
                  ),
                  const SizedBox(height: 14),
                  const Center(
                    child: Text(
                      'Start with a GitHub username',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Try torvalds, gaearon, or flutter.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchBox() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: purple.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(
            Icons.search,
            color: purple,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchUser(),
              decoration: const InputDecoration(
                hintText: 'Enter GitHub username',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          FilledButton(
            onPressed: _loading ? null : () => _searchUser(),
            style: FilledButton.styleFrom(
              backgroundColor: purple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.redAccent.withOpacity(0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard(GitHubUser user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF30234F),
            Color(0xFF1D1830),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: purple.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: purple.withOpacity(0.2),
                backgroundImage: user.avatar.isNotEmpty
                    ? NetworkImage(user.avatar)
                    : null,
                child: user.avatar.isEmpty
                    ? const Icon(
                        Icons.person,
                        size: 36,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name.isEmpty ? user.login : user.name,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@${user.login}',
                      style: const TextStyle(
                        color: purple,
                        fontSize: 14,
                      ),
                    ),
                    if (user.location.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        '📍 ${user.location}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open GitHub profile',
                onPressed: () => _openUrl(user.htmlUrl),
                icon: const Icon(
                  Icons.open_in_new,
                  color: purple,
                ),
              ),
            ],
          ),

          if (user.bio.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              user.bio,
              style: TextStyle(
                color: Colors.white.withOpacity(0.82),
                height: 1.4,
              ),
            ),
          ],

          const SizedBox(height: 22),

          Row(
            children: [
              _stat(
                'Repositories',
                user.publicRepos.toString(),
                Icons.folder_outlined,
              ),
              _stat(
                'Followers',
                user.followers.toString(),
                Icons.people_outline,
              ),
              _stat(
                'Following',
                user.following.toString(),
                Icons.person_add_alt_1,
              ),
            ],
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openUrl(user.htmlUrl),
              icon: const Icon(Icons.open_in_new),
              label: const Text('View GitHub profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: purple.withOpacity(0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(
    String label,
    String value,
    IconData icon,
  ) {
    return Expanded(
      child: Column(
        children: [
          Icon(
            icon,
            color: purple,
            size: 20,
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.58),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(
    String title,
    String subtitle,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _repoCard(GitHubRepo repo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        onTap: () => _openUrl(repo.url),
        leading: Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: purple.withOpacity(0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.folder_copy_outlined,
            color: purple,
          ),
        ),
        title: Text(
          repo.name,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (repo.description.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                repo.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (repo.language.isNotEmpty) ...[
                  const Icon(
                    Icons.circle,
                    size: 9,
                    color: purple,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    repo.language,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 14),
                ],
                const Icon(
                  Icons.star_border,
                  size: 16,
                  color: Colors.amber,
                ),
                const SizedBox(width: 3),
                Text(
                  '${repo.stars}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(
          Icons.arrow_outward,
          size: 18,
        ),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withOpacity(0.65),
        ),
      ),
    );
  }
}