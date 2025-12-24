/// Workspace 模型
/// 表示一个工作空间（账本）

class Workspace {
  final int id;
  final String name;
  final String? description;
  final int ownerId;
  final String storageType; // 'local' 或 'server'
  final bool isShared;
  final String? createdAt;
  final String? updatedAt;

  Workspace({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    required this.storageType,
    required this.isShared,
    this.createdAt,
    this.updatedAt,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      ownerId: json['ownerId'] as int? ?? json['owner_id'] as int,
      storageType: json['storage_type'] as String? ?? json['storageType'] as String? ?? 'server',
      isShared: json['is_shared'] as bool? ?? json['isShared'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? json['createdAt'] as String?,
      updatedAt: json['updated_at'] as String? ?? json['updatedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'ownerId': ownerId,
      'storage_type': storageType,
      'is_shared': isShared,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  Workspace copyWith({
    int? id,
    String? name,
    String? description,
    int? ownerId,
    String? storageType,
    bool? isShared,
    String? createdAt,
    String? updatedAt,
  }) {
    return Workspace(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      storageType: storageType ?? this.storageType,
      isShared: isShared ?? this.isShared,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Workspace 成员模型
class WorkspaceMember {
  final int id;
  final int workspaceId;
  final int userId;
  final String username;
  final String role; // 'owner', 'admin', 'editor', 'viewer'
  final String? permissions;
  final int? invitedBy;
  final String? invitedByUsername;
  final String? joinedAt;

  WorkspaceMember({
    required this.id,
    required this.workspaceId,
    required this.userId,
    required this.username,
    required this.role,
    this.permissions,
    this.invitedBy,
    this.invitedByUsername,
    this.joinedAt,
  });

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    return WorkspaceMember(
      id: json['id'] as int,
      workspaceId: json['workspaceId'] as int? ?? json['workspace_id'] as int,
      userId: json['userId'] as int? ?? json['user_id'] as int,
      username: json['username'] as String,
      role: json['role'] as String,
      permissions: json['permissions'] as String?,
      invitedBy: json['invited_by'] as int? ?? json['invitedBy'] as int?,
      invitedByUsername: json['invited_by_username'] as String? ?? json['invitedByUsername'] as String?,
      joinedAt: json['joined_at'] as String? ?? json['joinedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspaceId': workspaceId,
      'userId': userId,
      'username': username,
      'role': role,
      if (permissions != null) 'permissions': permissions,
      if (invitedBy != null) 'invited_by': invitedBy,
      if (invitedByUsername != null) 'invited_by_username': invitedByUsername,
      if (joinedAt != null) 'joined_at': joinedAt,
    };
  }
}

/// Workspace 邀请模型
class WorkspaceInvitation {
  final int id;
  final int workspaceId;
  final String workspaceName;
  final String? email;
  final int? userId;
  final String? invitedUsername;
  final String role;
  final String token;
  final int invitedBy;
  final String invitedByUsername;
  final String expiresAt;
  final String status; // 'pending', 'accepted', 'rejected', 'expired'
  final String createdAt;

  WorkspaceInvitation({
    required this.id,
    required this.workspaceId,
    required this.workspaceName,
    this.email,
    this.userId,
    this.invitedUsername,
    required this.role,
    required this.token,
    required this.invitedBy,
    required this.invitedByUsername,
    required this.expiresAt,
    required this.status,
    required this.createdAt,
  });

  factory WorkspaceInvitation.fromJson(Map<String, dynamic> json) {
    return WorkspaceInvitation(
      id: json['id'] as int,
      workspaceId: json['workspaceId'] as int? ?? json['workspace_id'] as int,
      workspaceName: json['workspace_name'] as String? ?? json['workspaceName'] as String? ?? '',
      email: json['email'] as String?,
      userId: json['userId'] as int? ?? json['user_id'] as int?,
      invitedUsername: json['invited_username'] as String? ?? json['invitedUsername'] as String?,
      role: json['role'] as String,
      token: json['token'] as String,
      invitedBy: json['invited_by'] as int? ?? json['invitedBy'] as int,
      invitedByUsername: json['invited_by_username'] as String? ?? json['invitedByUsername'] as String? ?? '',
      expiresAt: json['expires_at'] as String? ?? json['expiresAt'] as String? ?? '',
      status: json['status'] as String,
      createdAt: json['created_at'] as String? ?? json['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspaceId': workspaceId,
      'workspace_name': workspaceName,
      if (email != null) 'email': email,
      if (userId != null) 'userId': userId,
      if (invitedUsername != null) 'invited_username': invitedUsername,
      'role': role,
      'token': token,
      'invited_by': invitedBy,
      'invited_by_username': invitedByUsername,
      'expires_at': expiresAt,
      'status': status,
      'created_at': createdAt,
    };
  }
}




