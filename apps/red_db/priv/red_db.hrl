-record(redis_command, {
					timestamp :: float(),
          db = 0    :: non_neg_integer(),
          cmd       :: binary(),
          args = [] :: [term()],
          group        :: keys | strings | hashes | lists | sets | zsets | pub_sub | transactions | connection | server,
          result_type,
          timeout      :: undefined | infinity | pos_integer(),
          expire       :: undefined | never | pos_integer()
        }).

-record(red_item, {
				key :: binary(),
				value  :: binary()	
				}).
