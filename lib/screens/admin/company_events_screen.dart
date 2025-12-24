import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/admin_logger.dart';

class CompanyEventsScreen extends StatefulWidget {
  final String companyId;
  const CompanyEventsScreen({super.key, required this.companyId});

  @override
  State<CompanyEventsScreen> createState() => _CompanyEventsScreenState();
}

class _CompanyEventsScreenState extends State<CompanyEventsScreen> {
  List<Map<String, dynamic>> events = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadEvents();
  }

  Future<void> loadEvents() async {
    setState(() => loading = true);
    try {
      final data = await Supabase.instance.client
          .from('company_events')
          .select()
          .eq('company_id', widget.companyId)
          .order('created_at', ascending: false);
      setState(() {
        events = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
      // Ignore error if table doesn't exist yet, just show empty
    }
  }

  Future<void> _deleteEvent(String eventId) async {
    try {
      await Supabase.instance.client
          .from('company_events')
          .delete()
          .eq('id', eventId);
      loadEvents();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка удаления: $e')),
      );
    }
  }

  void _showAddEventDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AddEventDialog(companyId: widget.companyId, onSave: loadEvents),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Акции и Ивенты')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddEventDialog,
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : events.isEmpty
              ? const Center(child: Text('Нет акций'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (event['image_url'] != null)
                            SizedBox(
                              height: 150,
                              width: double.infinity,
                              child: Image.network(
                                event['image_url'],
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
                              ),
                            ),
                          ListTile(
                            title: Text(event['title'] ?? 'Без названия', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(event['description'] ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteEvent(event['id']),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class AddEventDialog extends StatefulWidget {
  final String companyId;
  final VoidCallback onSave;

  const AddEventDialog({super.key, required this.companyId, required this.onSave});

  @override
  State<AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<AddEventDialog> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  File? _imageFile;
  bool _uploading = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
      });
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.isEmpty) return;

    setState(() => _uploading = true);
    try {
      String? imageUrl;
      if (_imageFile != null) {
        final fileExt = _imageFile!.path.split('.').last;
        final fileName = '${widget.companyId}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        
        // Ensure bucket exists or handle error
        try {
          await Supabase.instance.client.storage
              .from('event_images')
              .upload(fileName, _imageFile!);
          
          imageUrl = Supabase.instance.client.storage
              .from('event_images')
              .getPublicUrl(fileName);
        } catch (e) {
          debugPrint('Storage error: $e');
          // Continue without image or handle error
        }
      }

      await Supabase.instance.client.from('company_events').insert({
        'company_id': widget.companyId,
        'title': _titleCtrl.text,
        'description': _descCtrl.text,
        'image_url': imageUrl,
      });

      await AdminLogger.log('create_event', 'Создана акция: ${_titleCtrl.text}');
      
      widget.onSave();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить акцию'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                  image: _imageFile != null
                      ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)
                      : null,
                ),
                child: _imageFile == null
                    ? const Icon(Icons.add_a_photo, size: 40, color: Colors.grey)
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Заголовок'),
            ),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Описание'),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: _uploading ? null : _save,
          child: _uploading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Создать'),
        ),
      ],
    );
  }
}
