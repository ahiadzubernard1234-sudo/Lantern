import 'package:lantern/core/database/database_service.dart';
import 'package:lantern/core/network/network_service.dart';
import 'package:lantern/core/network/peer_discovery_service.dart';
import 'package:lantern/features/chat/data/datasources/local_message_datasource.dart';
import 'package:lantern/features/chat/data/repositories/message_repository_impl.dart';
import 'package:lantern/features/chat/domain/repositories/message_repository.dart';
import 'package:lantern/features/channels/data/datasources/local_channel_datasource.dart';
import 'package:lantern/features/channels/data/repositories/channel_repository_impl.dart';
import 'package:lantern/features/channels/domain/repositories/channel_repository.dart';
import 'package:lantern/features/profile/data/datasources/local_profile_datasource.dart';
import 'package:lantern/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:lantern/features/profile/domain/repositories/profile_repository.dart';

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();

  late DatabaseService _databaseService;
  late NetworkService _networkService;
  late PeerDiscoveryService _peerDiscoveryService;

  late LocalProfileDatasource _localProfileDatasource;
  late ProfileRepository _profileRepository;

  late LocalMessageDatasource _localMessageDatasource;
  late MessageRepository _messageRepository;

  late LocalChannelDatasource _localChannelDatasource;
  late ChannelRepository _channelRepository;

  factory ServiceLocator() {
    return _instance;
  }

  ServiceLocator._internal();

  Future<void> initialize() async {
    // Initialize core services
    _databaseService = DatabaseService();
    await _databaseService.initialize();

    _networkService = NetworkService();
    _peerDiscoveryService = PeerDiscoveryService(_networkService);

    // Initialize datasources
    _localProfileDatasource = LocalProfileDatasource(_databaseService);
    _localMessageDatasource = LocalMessageDatasource(_databaseService);
    _localChannelDatasource = LocalChannelDatasource(_databaseService);

    // Initialize repositories
    _profileRepository = ProfileRepositoryImpl(_localProfileDatasource);
    _messageRepository = MessageRepositoryImpl(_localMessageDatasource, _networkService, _localProfileDatasource);
    _channelRepository = ChannelRepositoryImpl(_localChannelDatasource, _networkService);
  }

  // Getters
  DatabaseService get databaseService => _databaseService;
  NetworkService get networkService => _networkService;
  PeerDiscoveryService get peerDiscoveryService => _peerDiscoveryService;
  ProfileRepository get profileRepository => _profileRepository;
  MessageRepository get messageRepository => _messageRepository;
  ChannelRepository get channelRepository => _channelRepository;
}

Future<void> setupServiceLocator() async {
  await ServiceLocator().initialize();
}
