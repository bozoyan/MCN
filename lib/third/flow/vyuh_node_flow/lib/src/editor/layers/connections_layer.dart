import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../../connections/connection.dart';
import '../../connections/connections_canvas.dart';
import '../../connections/styles/connection_style_base.dart';
import '../../plugins/lod/lod_plugin.dart';
import '../controller/node_flow_controller.dart';
import '../themes/node_flow_theme.dart';

/// Connections layer widget that renders all connections between nodes
class ConnectionsLayer<T, C> extends StatelessWidget {
  const ConnectionsLayer({
    super.key,
    required this.controller,
    this.animation,
    this.connectionStyleBuilder,
  });

  final NodeFlowController<T, C> controller;
  final Animation<double>? animation;
  final ConnectionStyleBuilder<T, C>? connectionStyleBuilder;

  @override
  Widget build(BuildContext context) {
    final lod = controller.lod;

    // IgnorePointer ensures connections don't block hit tests on layers below
    return Positioned.fill(
      child: IgnorePointer(
        // If LOD extension is not configured, skip the LOD Observer check
        child: lod == null
            ? _buildConnectionsStack(context)
            : Observer(
                builder: (context) {
                  // LOD check: hide connections when zoomed out
                  if (!lod.showConnectionLines) {
                    return const SizedBox.shrink();
                  }
                  return _buildConnectionsStack(context);
                },
              ),
      ),
    );
  }

  Widget _buildConnectionsStack(BuildContext context) {
    return Stack(
      children: [
        // Stationary connections: isolate static paths from animated paths.
        RepaintBoundary(
          child: Observer(
            builder: (context) {
              final theme = controller.theme ?? NodeFlowTheme.light;
              final visibleConnections = controller.visibleConnections;
              final activeIds = controller.activeConnectionIds;

              if (!controller.isConnectionPainterInitialized) {
                return const SizedBox.shrink();
              }

              // Filter out active connections
              final stationaryConnections = visibleConnections
                  .where((c) => !activeIds.contains(c.id))
                  .toList();
              final staticConnections = <Connection<C>>[];
              final animatedConnections = <Connection<C>>[];

              // Dependency tracking for static connections
              // This ensures we repaint if these nodes move (e.g. external update)
              // or visibility changes, but NOT when active nodes move
              controller.selectedConnectionIds.length;
              for (final connection in stationaryConnections) {
                final sourceNode = controller.getNode(connection.sourceNodeId);
                final targetNode = controller.getNode(connection.targetNodeId);

                if (sourceNode != null) {
                  sourceNode.position.value;
                  sourceNode.isVisible;
                }
                if (targetNode != null) {
                  targetNode.position.value;
                  targetNode.isVisible;
                }

                final effect = connection.getEffectiveAnimationEffect(
                  theme.connectionTheme.animationEffect,
                );
                if (effect == null || animation == null) {
                  staticConnections.add(connection);
                } else {
                  animatedConnections.add(connection);
                }
              }

              return Stack(
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: ConnectionsCanvas<T, C>(
                        store: controller,
                        theme: theme,
                        connectionPainter: controller.connectionPainter,
                        connections: staticConnections,
                        selectedIds: controller.selectedConnectionIds,
                        connectionStyleBuilder: connectionStyleBuilder,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: ConnectionsCanvas<T, C>(
                        store: controller,
                        theme: theme,
                        connectionPainter: controller.connectionPainter,
                        connections: animatedConnections,
                        selectedIds: controller.selectedConnectionIds,
                        animation: animatedConnections.isEmpty
                            ? null
                            : animation,
                        connectionStyleBuilder: connectionStyleBuilder,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // Active connections layer (No RepaintBoundary)
        // Renders ONLY active connections (attached to dragged/resized nodes)
        // Updates frequently (60fps) during interaction
        Observer(
          builder: (context) {
            final theme = controller.theme ?? NodeFlowTheme.light;
            final activeIds = controller.activeConnectionIds;

            if (!controller.isConnectionPainterInitialized) {
              return const SizedBox.shrink();
            }

            if (activeIds.isEmpty) return const SizedBox.shrink();

            // Get active connections
            final activeConnections = controller.connections
                .where((c) => activeIds.contains(c.id))
                .toList();

            // Dependency tracking for active connections
            // This triggers repaint on every frame of drag
            for (final connection in activeConnections) {
              final sourceNode = controller.getNode(connection.sourceNodeId);
              final targetNode = controller.getNode(connection.targetNodeId);

              if (sourceNode != null) {
                sourceNode.position.value;
                sourceNode.isVisible;
              }
              if (targetNode != null) {
                targetNode.position.value;
                targetNode.isVisible;
              }

              connection.animationEffect;
            }

            return CustomPaint(
              painter: ConnectionsCanvas<T, C>(
                store: controller,
                theme: theme,
                connectionPainter: controller.connectionPainter,
                connections: activeConnections,
                selectedIds: controller.selectedConnectionIds,
                animation: animation,
                connectionStyleBuilder: connectionStyleBuilder,
              ),
              size: Size.infinite,
            );
          },
        ),
      ],
    );
  }
}
