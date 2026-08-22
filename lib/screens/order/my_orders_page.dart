import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/order_provider.dart';
import '../../models/order.dart';
import '../order/create_order_screen.dart';
import 'order_detail_screen.dart';
import '../../models/role.dart';
import '../../widgets/common_app_bar.dart';
import 'package:go_router/go_router.dart';

class MyOrdersPage extends StatelessWidget {
  final String currentUserId;
  final String currentUserRole;

  const MyOrdersPage({
    Key? key,
    required this.currentUserId,
    required this.currentUserRole,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final orderProvider = Provider.of<OrderProvider>(context);
    final title = currentUserRole == 'business' ? '내 견적(사업자)' : '내 견적(고객)';
    final myOrders = orderProvider.orders.where((order) => order.customerId == currentUserId).toList();
    
    print('MyOrdersPage - currentUserId: $currentUserId');
    print('MyOrdersPage - total orders in provider: ${orderProvider.orders.length}');
    print('MyOrdersPage - filtered orders for user: ${myOrders.length}');
    for (var order in orderProvider.orders) {
      print('Order: ${order.title}, customerId: ${order.customerId}');
    }

    return Scaffold(
      appBar: CommonAppBar(title: title),
      body: orderProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : myOrders.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
                  itemCount: myOrders.length,
                  itemBuilder: (context, index) => _buildOrderCard(myOrders[index], context),
                ),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton(
          onPressed: () => Navigator.pushNamed(context, '/create-order'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Order order, BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => context.push('/order-detail'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF102A43),
                      ),
                    ),
                  ),
                  _buildStatusChip(order.status),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                order.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(order.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  const Spacer(),
                  if (order.estimatedPrice > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C6AE).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${order.estimatedPrice.toStringAsFixed(0)}원',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00C6AE),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'pending':
        statusText = '대기 중';
        statusColor = const Color(0xFFFFA726);
        statusIcon = Icons.schedule;
        break;
      case 'in_progress':
        statusText = '진행 중';
        statusColor = const Color(0xFF2E74B5);
        statusIcon = Icons.work;
        break;
      case 'completed':
        statusText = '완료';
        statusColor = const Color(0xFF00C6AE);
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusText = '취소됨';
        statusColor = const Color(0xFFFF6B6B);
        statusIcon = Icons.cancel;
        break;
      default:
        statusText = '알 수 없음';
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: statusColor, size: 14),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '오늘';
    } else if (difference.inDays == 1) {
      return '어제';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return '${date.month}/${date.day}';
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF2E74B5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: const Color(0xFF2E74B5),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '아직 주문이 없습니다',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF102A43),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '새로운 주문을 만들어보세요',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/create-order'),
            icon: const Icon(Icons.add),
            label: const Text('주문하기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E74B5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
