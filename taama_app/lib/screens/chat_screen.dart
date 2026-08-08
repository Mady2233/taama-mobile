import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_service.dart';
import '../config/api_config.dart';
import '../theme/couleurs_taama.dart';

/// Écran de chat en temps réel entre passager et conducteur.
///
/// Paramètres :
/// - roomName : identifiant unique de la conversation ("demande_42" ou
///   "reservation_7") — correspond à la salle WebSocket côté backend
/// - titreConversation : nom affiché dans l'AppBar (nom du conducteur ou
///   du passager selon le contexte)
class EcranChat extends StatefulWidget {
  final String roomName;
  final String titreConversation;

  const EcranChat({
    super.key,
    required this.roomName,
    required this.titreConversation,
  });

  @override
  State<EcranChat> createState() => _EcranChatState();
}

class _EcranChatState extends State<EcranChat> {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _connecte = false;
  bool _erreur = false;

  static final String _wsBaseUrl = ApiConfig.wsUrl;

  @override
  void initState() {
    super.initState();
    _connecter();
  }

  @override
  void dispose() {
    // J'annule l'abonnement AVANT de fermer le socket : sinon, close()
    // déclenche onDone de façon synchrone et setState() plante car le
    // widget est déjà en cours de démontage (mounted ne le détecte pas ici).
    _subscription?.cancel();
    _channel?.sink.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _connecter() {
    final token = ApiService.token;
    if (token == null) return;

    final uri = Uri.parse(
      '$_wsBaseUrl/ws/chat/${widget.roomName}/?token=$token',
    );

    try {
      _channel = WebSocketChannel.connect(uri);
      debugPrint('WebSocket connecté sur : $uri');
      setState(() {
        _connecte = true;
        _erreur = false;
      });

      _subscription = _channel!.stream.listen(
        (data) {
          final message = jsonDecode(data?.toString() ?? '') ?? {};
          if (!mounted) return;
          setState(() => _messages.add(message));
          _scrollerEnBas();
        },
        onError: (e) {
          debugPrint('WebSocket erreur : $e');
          if (!mounted) return;
          setState(() => _erreur = true);
        },
        onDone: () {
          debugPrint('WebSocket fermé');
          if (!mounted) return;
          setState(() => _connecte = false);
        },
      );
    } catch (e) {
      setState(() => _erreur = true);
    }
  }

  void _envoyerMessage() {
    final texte = _messageController.text.trim();
    if (texte.isEmpty || _channel == null) return;

    _channel!.sink.add(jsonEncode({'message': texte}));
    _messageController.clear();
  }

  void _scrollerEnBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.titreConversation, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              _connecte ? 'En ligne' : (_erreur ? 'Erreur de connexion' : 'Déconnecté'),
              style: TextStyle(
                fontSize: 12,
                color: _connecte ? Colors.green.shade300 : Colors.red.shade300,
              ),
            ),
          ],
        ),
        backgroundColor: CouleursTaama.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_erreur || !_connecte)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _subscription?.cancel();
                _channel?.sink.close();
                setState(() => _messages.clear());
                _connecter();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Aucun message pour l\'instant.\nDis bonjour !',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final estMoi = message['moi'] as bool? ?? false;
                      return _BulleMessage(message: message, estMoi: estMoi);
                    },
                  ),
          ),
          _ZoneSaisie(
            controller: _messageController,
            onEnvoyer: _envoyerMessage,
            actif: _connecte,
          ),
        ],
      ),
    );
  }
}

class _BulleMessage extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool estMoi;

  const _BulleMessage({required this.message, required this.estMoi});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: estMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: estMoi ? CouleursTaama.terreCuite : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(estMoi ? 16 : 4),
            bottomRight: Radius.circular(estMoi ? 4 : 16),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!estMoi)
              Text(
                message['expediteur_nom'] as String? ?? '',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: CouleursTaama.terreCuite,
                ),
              ),
            Text(
              message['message']?.toString() ?? '',
              style: TextStyle(color: estMoi ? Colors.white : Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneSaisie extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onEnvoyer;
  final bool actif;

  const _ZoneSaisie({
    required this.controller,
    required this.onEnvoyer,
    required this.actif,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: actif,
                decoration: InputDecoration(
                  hintText: actif ? 'Écris un message...' : 'Connexion en cours...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onEnvoyer(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: actif ? onEnvoyer : null,
              child: CircleAvatar(
                backgroundColor: actif ? CouleursTaama.terreCuite : Colors.grey.shade300,
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}