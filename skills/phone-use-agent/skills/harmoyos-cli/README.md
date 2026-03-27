当前pc上插有harmonyos手机，使用hdc shell命令，可以进入harmonyos手机内部执行命令；
也可以通过hdc shell "xxx"直接执行命令；
我现在想统计harmonyos设备中支持的全量命令，请帮我挨个测试，无论是使用help/-h方式查看说明，还是实际执行查看效果；
最后给我输出一份精准的统计报告；报告需要包含共支持多少个CLI命令，分别是什么作用，完整的命令操作指导；


1. 下面是官方开发者文档给出的一些命令举例，可以挨个查看；
SDK命令行工具简介
hdc
aa工具
bm工具
打包拆包工具
扫描工具
cem工具
anm工具
edm工具
restool工具
param工具
power-shell工具
atm工具
network-cfg工具
hilog
hilogtool
hidumper
hitrace
hiperf
hiprofiler
uinput
命令行工具
二进制签名工具

其中hidumper命令后面可以跟各种不同的系统服务，请列出所有系统服务支持的命令；

2. 除了以上这些命令外，系统内基础的unix/linux命令也请给出来；

3. 请探索系统内/bin、/system/bin等各种可能包含CLI命令的目录，进行测试总结；