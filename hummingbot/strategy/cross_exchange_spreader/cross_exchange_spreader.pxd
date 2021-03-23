# distutils: language=c++

from libc.stdint cimport int64_t
from hummingbot.core.data_type.limit_order cimport LimitOrder
from hummingbot.strategy.strategy_base cimport StrategyBase
from .order_id_market_pair_tracker import OrderIDMarketPairTracker

cdef class CrossExchangeSpreaderStrategy(StrategyBase):
    cdef:
        set _maker_markets
        set _ref_markets
        set _hedge_markets
        object _order_amount
        double _order_spread
        double _status_report_interval
        int64_t _logging_options
        OrderIDMarketPairTracker _market_pair_tracker
        bint _hb_app_notification
        list _maker_order_ids

    cdef c_process_market_pair(self,
                               object market_pair,
                               list active_ddex_orders)

    cdef object c_get_order_size_after_portfolio_ratio_limit(self,
                                                             object market_pair)

    cdef object c_get_adjusted_limit_order_size(self,
                                                object market_pair)

    cdef object c_get_market_making_size(self,
                                         object market_pair,
                                         bint is_bid)

    cdef object c_get_market_making_price(self,
                                          object market_pair,
                                          bint is_bid,
                                          object size)

    cdef bint c_check_if_sufficient_balance(self,
                                            object market_pair,
                                            LimitOrder active_order)

    cdef tuple c_get_top_bid_ask(self,
                                 object market_pair)

    cdef tuple c_get_top_bid_ask_from_price_samples(self,
                                                    object market_pair)

    cdef tuple c_get_suggested_price_samples(self,
                                             object market_pair)

    cdef c_take_suggested_price_sample(self,
                                       object market_pair)

    cdef c_check_and_create_new_orders(self,
                                       object market_pair,
                                       bint has_active_bid,
                                       bint has_active_ask)

    cdef str c_place_order(self,
                           object market_pair,
                           bint is_buy,
                           bint is_maker,
                           object amount,
                           object price)
