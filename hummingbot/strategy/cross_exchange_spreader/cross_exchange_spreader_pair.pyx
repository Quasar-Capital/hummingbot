import logging
from collections import defaultdict
from typing import List, Tuple, Optional
from decimal import Decimal
from libc.stdint cimport int64_t

from hummingbot.core.clock cimport Clock
from hummingbot.strategy.strategy_base cimport StrategyBase
from hummingbot.strategy.strategy_base import StrategyBase
from hummingbot.connector.exchange_base cimport ExchangeBase
from hummingbot.connector.exchange_base import ExchangeBase
from hummingbot.core.data_type.limit_order cimport LimitOrder
from hummingbot.core.data_type.limit_order import LimitOrder
from hummingbot.core.event.events import OrderType
from hummingbot.core.network_iterator import NetworkStatus

from .cross_exchange_spreader_pair import CrossExchangeSpreaderPair
from .order_id_market_pair_tracker import OrderIDMarketPairTracker

NaN = float("nan")
s_logger = None
s_decimal_zero = Decimal(0)
s_decimal_nan = Decimal("nan")

cdef class CrossExchangeSpreaderStrategy(StrategyBase):
    OPTION_LOG_NULL_ORDER_SIZE = 1 << 0
    OPTION_LOG_REMOVING_ORDER = 1 << 1
    OPTION_LOG_ADJUST_ORDER = 1 << 2
    OPTION_LOG_CREATE_ORDER = 1 << 3
    OPTION_LOG_MAKER_ORDER_FILLED = 1 << 4
    OPTION_LOG_STATUS_REPORT = 1 << 5
    OPTION_LOG_MAKER_ORDER_HEDGED = 1 << 6
    OPTION_LOG_ALL = 0x7fffffffffffffff

    @classmethod
    def logger(cls):
        global s_logger

        if s_logger is None:
            s_logger = logging.getLogger(__name__)
        return s_logger

    def __init__(self,
                 market_pairs: List[CrossExchangeSpreaderPair],
                 order_amount: Optional[Decimal] = Decimal("0.0"),
                 logging_options: int = OPTION_LOG_ALL,
                 status_report_interval: float = 900,
                 hb_app_notification: bool = False
                 ):
        """
        Initializes a cross exchange spreader market making strategy object.

        :param market_pairs: list of cross exchange market pairs
        :param order_amount: override the limit order trade size, in base asset units
        :param logging_options: bit field for what types of logging to enable in this strategy object
        :param status_report_interval: what is the time interval between outputting new network warnings
        :param hb_app_notification: notify hummingbird app
        """

        if len(market_pairs) < 0:
            raise ValueError(f"market_pairs must not be empty.")

        super().__init__()

        self._market_pairs = {
            (market_pair.maker.market, market_pair.maker.trading_pair): market_pair for market_pair in market_pairs
        }
        self._maker_markets = set([market_pair.maker.market for market_pair in market_pairs])
        self._ref_markets = set([market_pair.ref.market for market_pair in market_pairs])
        self._taker_markets = set([market_pair.taker.market for market_pair in market_pairs])
        self._market_pair_tracker = OrderIDMarketPairTracker()
        self._all_markets_ready = False
        self._logging_options = <int64_t> logging_options
        self._status_report_interval = status_report_interval
        self._last_timestamp = 0
        self._hb_app_notification = hb_app_notification
        self._maker_order_ids = []

        cdef:
            list all_markets = list(self._maker_markets | self._ref_markets | self._maker_markets)

        self.c_add_markets(all_markets)

    @property
    def active_limit_orders(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return [(ex, order) for ex, order in self._sb_order_tracker.active_limit_orders
                if order.client_order_id in self._maker_order_ids]

    @property
    def cached_limit_orders(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return self._sb_order_tracker.shadow_limit_orders

    @property
    def active_bids(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return [(market, limit_order) for market, limit_order in self.active_limit_orders if limit_order.is_buy]

    @property
    def active_asks(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return [(market, limit_order) for market, limit_order in self.active_limit_orders if not limit_order.is_buy]

    @property
    def logging_options(self) -> int:
        return self._logging_options

    @logging_options.setter
    def logging_options(self, int64_t logging_options):
        self._logging_options = logging_options

    cdef c_start(self, Clock clock, double timestamp):
        StrategyBase.c_start(self, clock, timestamp)
        self._last_timestamp = timestamp

    cdef c_tick(self, double timestamp):
        StrategyBase.c_tick(self, timestamp)

        cdef:
            int64_t current_tick = <int64_t> (timestamp // self._status_report_interval)
            int64_t last_tick = <int64_t> (self._last_timestamp // self._status_report_interval)
            bint should_report_warnings = ((current_tick > last_tick) and
                                           (self._logging_options & self.OPTION_LOG_STATUS_REPORT))
            list active_limit_orders = self.active_limit_orders
            LimitOrder limit_order

        try:
            self._market_pair_tracker.c_tick(timestamp)

            if not self._all_markets_ready:
                self._all_markets_ready = all([market.ready for market in self._sb_markets])

                if not self._all_markets_ready:
                    if should_report_warnings:
                        self.logger().warning(f"Markets are not ready. Please wait.")

            if should_report_warnings:
                if not all([market.network_status in NetworkStatus.CONNECTED for market in self._sb_markets]):
                    self.logger().warning(f"WARNING: Some markets are not connected or are down at the moment.")

            market_pair_to_active_orders = defaultdict(list)

            for maker_market, limit_order in active_limit_orders:
                market_pair = self._market_pairs.get((maker_market, limit_order.trading_pair))

                if market_pair is None:
                    self.log_with_clock(logging.WARNING,
                                        f"In-flight maker order for trading pair '{limit_order.trading_pair}' "
                                        f"does not correspond to any whitelisted trading pairs. Skipping.")
                    continue

                if not self._sb_order_tracker.c_has_in_flight_cancel(
                        limit_order.client_order_id) and limit_order.client_order_id in self._maker_order_ids:
                    market_pair_to_active_orders[market_pair].append(limit_order)

            for market_pair in self._market_pairs.values():
                self.c_process_market_pair(market_pair, market_pair_to_active_orders[market_pair])

        finally:
            self._last_timestamp = timestamp

    cdef c_process_market_pair(self, object market_pair, list active_orders):
        """
        For each market pair:

        1. Check if any existing orders need to be cancelled
        2. Check if new orders should be created

        For each market pair, only 1 active bid and ask is allowed.

        :param market_pair: cross exchange market pai
        :param active_orders: list of active limit orders associated with the market pair
        """
        cdef:
            ExchangeBase taker_market
            bint is_buy
            bint has_active_bid = False
            bint has_active_ask = False
            bin need_adjust_order = False

        global s_decimal_zero

        # self.c_take_suggested_price_sample(market_pair)

        for active_order in active_orders:
            # Mark the has_active_bid and has_active_ask flags
            is_buy = active_order.is_buy
            if is_buy:
                has_active_bid = True
            else:
                has_active_ask = True

        # TODO: Think through what needs to be done here

    cdef c_check_and_create_new_orders(self, object market_pair, bint has_active_bid, bint has_active_ask):
        pass

    cdef str c_place_order(self,
                           object market_pair,
                           bint is_buy,
                           bint is_maker,
                           object amount,
                           object price):
        cdef:
            str order_id
            double expiration_seconds = NaN
            object market_info = market_pair.market if is_maker else market_pair.taker
            object order_type = market_info.market.get_maker_order_type() if is_maker else market_info.market.get_taker_order_type()

        if order_type is OrderType.MARKET:
            price = s_decimal_nan

        # TODO: decide later if we need orders to expire
        if is_buy:
            order_id = StrategyBase.c_buy_with_specific_market(self, market_info, amount, order_type=order_type,
                                                               price=price, expiration_seconds=expiration_seconds)
        else:
            order_id = StrategyBase.c_sell_with_specific_market(self, market_info, amount, order_type=order_type,
                                                                price=price, expiration_seconds=expiration_seconds)

        self._sb_order_tracker.c_add_create_order_pending(order_id)
        self._market_pair_tracker.c_start_tracking_order_id(order_id, market_info.market, market_pair)

        if is_maker:
            self._maker_order_ids.append(order_id)

        return order_id

    cdef c_cancel_order(self, object market_pair, str order_id):
        market_trading_pair_tuple = self._sb_order_tracker.c_get_market_pair_from_order_id(order_id)
        StrategyBase.c_cancel_order(self, market_trading_pair_tuple, order_id)

    # Removes orders from pending_create
    cdef c_remove_create_order_pending(self, order_id):
        self._sb_order_tracker.c_remove_create_order_pending(order_id)

    cdef c_did_create_buy_order(self, object order_created_event):
        self.c_remove_create_order_pending(order_created_event.order_id)

    cdef c_did_create_sell_order(self, object order_created_event):
        self.c_remove_create_order_pending(order_created_event.order_id)

    def notify_hb_app(self, msg: str):
        if self._hb_app_notification:
            from hummingbot.client.hummingbot_application import HummingbotApplication
            HummingbotApplication.main_application()._notify(msg)
