#!/usr/bin/python
# -*- coding: UTF-8 -*-
import os
import sys
import re
import rumps
from AppKit import NSScreen, NSLocale
version = '0.1.1'
lang = NSLocale.preferredLanguages()[0].replace('-','_')

# pyinstaller资源目录访问函数
def resource_path(relative_path):
	if getattr(sys, 'frozen', False):
		base_path = sys._MEIPASS
	else:
		base_path = os.path.abspath(".")
	return os.path.join(base_path, relative_path)

# 本地化字符串函数
def trans(string):
	zh_Hans_CN = {"Quit":u"退出", "About":u"关于", "No VMs":u"无虚拟机", "Start all VMs":u"全部启动", "Stop all VMs":u"全部停止"}
	try:
		text = locals()[lang][string]
	except:
		text = string
	return text

# 实现启动指定客户机的函数
def userclick(app, menuitem):
	os.popen("/usr/local/bin/prlctl start '"+menuitem.title+"'")
	os.popen("open -a 'Parallels Desktop'")

# 检测显示屏类型是否是retina, 并以此调用高清/低清菜单栏图标
HiDPi = NSScreen.mainScreen().backingScaleFactor()
micon = resource_path(os.path.join("res","menuicon@2x.png"))
if HiDPi == 1:
	micon = resource_path(os.path.join("res","menuicon.png"))

# 获取宿主机上安装的所有客户机名列表
vmlist = []
vms = re.sub('  +', ',', os.popen('/usr/local/bin/prlctl list -a|sed 1d').read().strip())
if vms != '':
	vmlist = re.sub('.*,', '', vms).split('\n')

class PDrunner(rumps.App):
	
	# 动态生成客户机列表项, 并绑定点击动作的回调函数
	for vm in vmlist:
		userclick = rumps.clicked(vm)(userclick)

	# 初始化列表结构
	def __init__(self):
		super(PDrunner, self).__init__("PDrunner")
		self.icon = micon
		self.template = True
		self.quit_button = trans("Quit")
		self.startall_button = rumps.MenuItem(title=trans("Start all VMs"), callback=self.startall)
		self.stopall_button = rumps.MenuItem(title=trans("Stop all VMs"), callback=self.stopall)
		self.about_button = rumps.MenuItem(title=trans("About")+"...", callback=self.about)
		self.novm = rumps.MenuItem(title=trans("No VMs"))
		self.novm.state = 0
		menu = [None,self.startall_button,self.stopall_button,None,self.about_button]
		vmlist.extend(menu)
		if vms == '':
			self.menu = [self.novm,None]
		else:
			self.menu = vmlist
	
	# 定义启动所有虚拟机的函数
	def startall(self, _):
		os.popen("open -a 'Parallels Desktop'")
		for vm in vmlist:
			os.popen("/usr/local/bin/prlctl start '"+vm+"'")
		
	# 定义关闭所有虚拟机的函数
	def stopall(self, _):
		vms = re.sub('  +', ',', os.popen('/usr/local/bin/prlctl list -a|sed 1d|tr -d {}|grep -v stopped').read().strip())
		vmlist = re.sub('.*,', '', vms).split('\n')
		for vm in vmlist:
			os.popen("/usr/local/bin/prlctl resume '"+vm+"'")
			os.popen("/usr/local/bin/prlctl stop '"+vm+"'")
	
	def about(self, _):
		rumps.alert(title=trans("About"), message="PDrunner v"+version+"\nby: lihaoyun6",ok="OK").run()
	
if __name__ == "__main__":
	PDrunner().run()
