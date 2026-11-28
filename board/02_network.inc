	cucc,vs010|cmcc,rax3000q|cmcc,rax3000qy)
		# WDS/AP 纯二层：不设 WAN 逻辑接口。桥成员不在这里猜默认路由，
		# 由运行期 bridge-netfix 读 sysfs（br-lan/brif + eth* + 无线口）动态补齐。
		# 不调用 ucidef_set_bridge 等函数：不同基线/DSA 版本函数名不一致，
		# 空分支最稳，绝不会因缺函数让 02_network 报错。
		;;
