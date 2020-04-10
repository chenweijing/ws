# penresty 依赖环境:
```
	Debain 和 Ubuntu
	apt-get install libpcre3-dev \
	    libssl-dev perl make build-essential curl

	centos:
	yum install pcre-devel openssl-devel gcc curl

	MAC OS X:
	brew update
	brew install pcre openssl
```

# 安装
```
	brew install openresty/brew/openresty

	或者
	把当前目录下的openresty-ubuntu-16.04 拷贝到系统目录下:
	mv openresty-ubuntu-16.04 /usr/local/openresty

	自定义安装，参考：
	http://openresty.org/cn/installation.html
```

# redis和业务接口放在了lua/config.lua.example中
```
   配置好后， 使用mv lua/config.lua.example lua/config.lua
```

# nginx.conf.example里面按照实际情况进行修改， 特别注意配置项如下：

```
   daemon on;                     	//<< 表运行示后台
   daemon off;                    	//<< 表运控制台运行
   error_log  /dev/stdout info;     //<< 表示日志输出到控制台
   error_log  logs/error.log  info; //<< 表示日志输出到logs目下的error.log文件中去. 注：logs目录必须手动先创建
   lua_shared_dict p2pcache 500m;   //<< 表示openresty共享内存分配大小，用于消息存储。
```

# 日志关键字
```
   JSON字段
   acction                 动作
   token                   登录token
   err_code                错误码
   err                     错误
   user_id                 用户id
   worker_id               工作进程ID
   time                    记录事件时间
   room_id                 房间ID
   session_id              套接字ID
   desc                    描述
   send_time_delay         发送最大延迟时间
   heartbeat               心跳包

   acction的值：
   login          			用户登录  // 如果登录有错误，会被记录
   logout                   用户退出  // 若果有错误，会被记录
   room_msg 				群消息
   room_manage				群管理消息(加入，退出，解散)
   redis_room_msg           redis 群消息
   redis_p2p_msg            redisedis_p2p消息
   redis_room_process_msg   redis房间管理/ 退出 进来 
   redis_connected_msg      redis连接消息
   memory_msg               内存消息
   web_err                  web 错误
   msg_send                 发送消息是错误
   wsconn                   client连接ws错误，一般是安全验证不通过
   msg_send                 发送消息错误查询
```

# 处理事件
```
   1 > 登录不成功查询
        action = login, token = ? 或者 action = wsconn ， token = ？ 进行查询

   2> 发送不成功查询
        action = msg_send, token = ?,  user_id = ?

   3> 掉线查询
        action = logout, token = ? (掉线原因非常多，ws前面是nginx，因此这边记录的退出事件是ngx与ws连接断开的事件)

   4> 发送延时查询
        send_time_delay is between 1 ~ 5 查询发送延时在1~5秒

   5> 全部收不到消息， 先排查redis情况
        action = redis_connected_msg （表示连接故障）
```