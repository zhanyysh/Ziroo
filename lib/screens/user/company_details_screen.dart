import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../map_screen.dart';

class CompanyDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> company;

  const CompanyDetailsScreen({super.key, required this.company});

  @override
  State<CompanyDetailsScreen> createState() => _CompanyDetailsScreenState();
}

class _CompanyDetailsScreenState extends State<CompanyDetailsScreen> {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await Supabase.instance.client
          .from('user_favorites')
          .select()
          .eq('user_id', userId)
          .eq('company_id', widget.company['id'])
          .maybeSingle();
      
      if (mounted) {
        setState(() {
          _isFavorite = data != null;
        });
      }
    } catch (e) {
      // ignore error
    }
  }

  Future<void> _toggleFavorite() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isFavorite = !_isFavorite);

    try {
      if (_isFavorite) {
        await Supabase.instance.client.from('user_favorites').insert({
          'user_id': userId,
          'company_id': widget.company['id'],
        });
      } else {
        await Supabase.instance.client
            .from('user_favorites')
            .delete()
            .eq('user_id', userId)
            .eq('company_id', widget.company['id']);
      }
    } catch (e) {
      setState(() => _isFavorite = !_isFavorite); // Revert
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _loadDetails() async {
    try {
      final client = Supabase.instance.client;
      
      // Load branches
      final branchesData = await client
          .from('company_branches')
          .select()
          .eq('company_id', widget.company['id']);

      // Load events
      final eventsData = await client
          .from('company_events')
          .select()
          .eq('company_id', widget.company['id'])
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _branches = List<Map<String, dynamic>>.from(branchesData);
          _events = List<Map<String, dynamic>>.from(eventsData);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки данных: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _openMap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MapScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final company = widget.company;
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(company['name'] ?? 'Магазин'),
              background: company['logo_url'] != null
                  ? Image.network(
                      company['logo_url'],
                      fit: BoxFit.cover,
                      errorBuilder: (_,__,___) => Container(color: Colors.grey),
                    )
                  : Container(
                      color: Colors.deepPurple,
                      child: const Icon(Icons.store, size: 60, color: Colors.white),
                    ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? Colors.red : Colors.white,
                ),
                onPressed: _toggleFavorite,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Discount Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Скидка ${company['discount_percentage']}%',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Description
                  const Text(
                    'О компании',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    company['description'] ?? 'Описание отсутствует',
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 24),

                  // Events Section
                  if (_events.isNotEmpty) ...[
                    const Text(
                      'Акции и новости',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          return Container(
                            width: 280,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                      image: event['image_url'] != null
                                          ? DecorationImage(
                                              image: NetworkImage(event['image_url']),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                      color: Colors.grey[300],
                                    ),
                                    child: event['image_url'] == null
                                        ? const Center(child: Icon(Icons.image_not_supported))
                                        : null,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        event['title'] ?? '',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (event['description'] != null)
                                        Text(
                                          event['description'],
                                          style: Theme.of(context).textTheme.bodySmall,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Branches Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Филиалы',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: _openMap,
                        icon: const Icon(Icons.map),
                        label: const Text('На карте'),
                      ),
                    ],
                  ),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_branches.isEmpty)
                    const Text('Нет информации о филиалах')
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _branches.length,
                      itemBuilder: (context, index) {
                        final branch = _branches[index];
                        return ListTile(
                          leading: const Icon(Icons.location_on, color: Colors.red),
                          title: Text(branch['name'] ?? 'Филиал'),
                          subtitle: Text('${branch['latitude']}, ${branch['longitude']}'),
                          onTap: () {
                            _openMap();
                          },
                        );
                      },
                    ),
                    
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
