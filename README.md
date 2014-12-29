fog
===

青蛙客户端，公主吻了青蛙，青蛙就变成了王子。	
目前只支持socks5代理
如何编译
--------

先修改./rel/files/sys.confing中的ip和端口为你自己的princess的ip和端口

	git https://github.com/DavidAlphaFox/fog.git
	cd fog
	make rel

如何使用
--------

	./rel/fog/bin/fog console
	ctrl-c 可以退出