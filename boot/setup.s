	.code16
# rewrite with AT&T syntax by falcon <wuzhangjin@gmail.com> at 081012
#
#	setup.s		(C) 1991 Linus Torvalds
#
# setup.s is responsible for getting the system data from the BIOS,
# and putting them into the appropriate places in system memory.
# both setup.s and system has been loaded by the bootblock.
#
# This code asks the bios for memory/disk/other parameters, and
# puts them in a "safe" place: 0x90000-0x901FF, ie where the
# boot-block used to be. It is then up to the protected mode
# system to read them from there before the area is overwritten
# for buffer-blocks.
# setup.s负责从BIOS 中获取系统数据，并将这些数据放到系统内存的适当地方。
# 此时setup.s 和system 已经由bootsect 引导块加载到内存中。
# 这段代码询问bios 有关内存/磁盘/其它参数，并将这些参数放到一个
# “安全的”地方：90000-901FF，也即原来bootsect 代码块曾经在
# 的地方，然后在被缓冲块覆盖掉之前由保护模式的system 读取。

# NOTE! These had better be the same as in bootsect.s!
# 以下这些参数最好和bootsect.s 中的相同
	.equ INITSEG, 0x9000	# we move boot here - out of the way 原来bootsect 所处的段
	.equ SYSSEG, 0x1000	# system loaded at 0x10000 (65536). system 在10000(64k)处。
	.equ SETUPSEG, 0x9020	# this is the current segment 本程序所在的段地址。

	.global _start, begtext, begdata, begbss, endtext, enddata, endbss
	.text
	begtext:
	.data
	begdata:
	.bss
	begbss:
	.text

	ljmp $SETUPSEG, $_start	
_start:

# ok, the read went well so we get current cursor position and save it for
# posterity. 整个读磁盘过程都正常，现在将光标位置保存以备今后使用。
# 将ds 置成INITSEG(9000)。这已经在bootsect 程序中设置过，但是现在是setup 程序，Linus 觉得需要再重新置一下。
	mov	$INITSEG, %ax	# this is done in bootsect already, but...
	mov	%ax, %ds
	mov	$0x03, %ah	# read cursor pos
	xor	%bh, %bh    #BIOS 中断10 的读光标功能号ah = 03 输入：bh = 页号 返回：ch = 扫描开始线，cl = 扫描结束线，
					#dh = 行号(00 是顶端)，dl = 列号(00 是左边)。返回值在dx中
	int	$0x10		# save it in known place, con_init fetches
	mov	%dx, %ds:0	# it from 0x90000. 将光标位置信息存放在90000 处，控制台初始化时会来取。
# Get memory size (extended mem, kB)

	mov	$0x88, %ah   #这3句取扩展内存的大小值（KB）。
	int	$0x15        #是调用中断15，功能号ah = 88 
					 #返回：ax = 从100000（1M）处开始的扩展内存大小(KB)。
					 #若出错则CF 置位，ax = 出错码。
	mov	%ax, %ds:2   #将ax中的返回值存放到90002处

# Get video-card data:
# 下面这段用于取显示卡当前显示模式。 调用BIOS 中断10，功能号ah = 0f
# 返回：ah = 字符列数，al = 显示模式，bh = 当前显示页。90004(1 字)存放当前页，90006 显示模式，90007 字符列数。
	mov	$0x0f, %ah
	int	$0x10
	mov	%bx, %ds:4	# bh = display page
	mov	%ax, %ds:6	# al = video mode, ah = window width

# check for EGA/VGA and some config parameters
# 检查显示方式（EGA/VGA）并取参数。 调用BIOS 中断10，附加功能选择-取方式信息
# 功能号：ah = 12，bl = 10 
# 返回：bh = 显示状态  
# (00 - 彩色模式，I/O 端口=3dX)  (01 - 单色模式，I/O 端口=3bX)
# bl = 安装的显示内存 (00 - 64k, 01 - 128k, 02 - 192k, 03 = 256k)
# cx = 显示卡特性参数(参见程序后的说明)。
	mov	$0x12, %ah
	mov	$0x10, %bl
	int	$0x10
	mov	%ax, %ds:8
	mov	%bx, %ds:10  #9000A = 安装的显示内存，9000B = 显示状态(彩色/单色)
	mov	%cx, %ds:12  #9000C = 显示卡特性参数。

# Get hd0 data
# 取第一个硬盘的信息（复制硬盘参数表）。 第1 个硬盘参数表的首地址竟然是中断向量41 的向量值！而第2 个硬盘
# 参数表紧接第1 个表的后面，中断向量46 的向量值也指向这第2 个硬盘的参数表首址。表的长度是16 个字节(10)。
# 面两段程序分别复制BIOS 有关两个硬盘的参数表，90080 处存放第1 个硬盘的表，90090 处存放第2 个硬盘的表。
	mov	$0x0000, %ax  #中断向量所在的地址
	mov	%ax, %ds   #给数据段寄存器赋值
	lds	%ds:4*0x41, %si #取中断向量41 的值，也即hd0 参数表的地址 ds:si，每个中断向量有4个字节？？
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0080, %di #传输的目的地址: 9000:0080 -> es:di
	mov	$0x10, %cx    # 共传输10 字节
	rep         #重复执行，直到cx为0.
	movsb

# Get hd1 data

	mov	$0x0000, %ax
	mov	%ax, %ds
	lds	%ds:4*0x46, %si  #取中断向量46 的值，也即hd1 参数表的地址 -> ds:si
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0090, %di   #传输的目的地址: 9000:0090 -> es:di
	mov	$0x10, %cx
	rep
	movsb

# Check that there IS a hd1 :-)
# 检查系统是否存在第2 个硬盘，如果不存在则第2 个表清零。利用BIOS 中断调用13 的取盘类型功能。
# 功能号ah = 15；
# 输入：dl = 驱动器号（8X 是硬盘：80 指第1 个硬盘，81 第2 个硬盘）
# 输出：ah = 类型码；00 --没有这个盘，CF 置位； 01 --是软驱，没有change-line 支持；
#  02--是软驱(或其它可移动设备)，有change-line 支持； 03 --是硬盘。

	mov	$0x01500, %ax
	mov	$0x81, %dl
	int	$0x13
	jc	no_disk1
	cmp	$3, %ah     #是硬盘吗？(类型= 3 ？)。
	je	is_disk1    #如果是硬盘，则跳到 is_disk1执行
no_disk1:
	mov	$INITSEG, %ax #第2个硬盘不存在，则对第2个硬盘表清零。
	mov	%ax, %es
	mov	$0x0090, %di
	mov	$0x10, %cx
	mov	$0x00, %ax
	rep
	stosb
is_disk1:

# now we want to move to protected mode ... 
#从这里开始我们要保护模式方面的工作了。

	cli			# no interrupts allowed !  关中断，此时不允许中断。

# first we move the system to it's rightful place
# 首先我们将system 模块移到正确的位置。
# bootsect 引导程序是将system 模块读入到3p0h3q3p2a2d0s3l1b1j1a1a1q1e1m1b0t1p1l1g9h2w2i2a2d0v3w3s3e3j1s3w1t1u9i0j9b0v1q1w1w9p8k7q7z7s1a1d0n1b9r9n0l0s3k0e1f0l3p2q2b1u3z1b0v0l3k3z3c2d2x0e1y0o0w9r9n1s2h1u1u3v4f1y2z0l1v9b9b9s9h2f2a3k3l4g1v0t0i7p8q7r8p0l8s8l8q8p8g1q0x1a1h2z1w9o9t1s3r1b2y3a1u1f3e1g0s1s1f1t1z2f1q0b9p9p1q1q1d1h1b1r9q1t1x0g9q2e0y0y1t9m0g0j0g8i8h8p8n8o8l0o8n0g1l0z0h0v0m2q2e1u3z2o3j3b3k0x1j4b0j2x3o0o1u0a0g9u0e9t9t1m1q1i0v0l4c2i1u2o0s2e2d2w0i1x8s8t8z9d8p8o8t7u8f7v0z0l0y3y3l3g3n3a9h9v9b1q3o1i1b1g1q1a1l1c0x1w3b3h0c0j0a2b9n1s3m1y1f2z1i1l9t9s0j1z1t2a0x1a1n9l8c8i8l8i8l8l0m0k8q8k0p8i1l0y1b3a3b1y9n9r1q1u1e1b3a1o2w1g1e0e1k0o3v2n2i0m2k1p1u0x1z3j3q3h3t9l9b2o2a2i2o3m3k3m1l0u7q8n0b0c8g7u0y1b0q9b1a3z2w3g3n3f2p2k9b1v4m3y0v0l3u3a3o3o3h1a1m4h2y0b9b2q2e1u3z3z2w3i3a0x0d9b0s0u0t0m1e1f0z9c7n0j0r0h0h0w0n0n7v8t1e0x4a2t0r0l2x2q2f1x3w4d3e3p3e3m3o0q1h2j3h0y0w2o2k2c2l1x1u2w4e3a3n0l1v2q9b2f1z9b0n0w0x1s9l8j8i8e8h8o8g7u0x0k0w0p7r1t0e3k3q3m2a2d9b1h1b2y3k2z3m0l1o0j1k2j2c1t0i0o9b9r8x2e3z3s1y2z0l1v2d2k2i2h9l9l3h2t4c1z0y0t0v0k7r8u7u8o0m8s8m8m1o0t1c1e1f0h1o1q1o1t1g3b1b3k3a1n1d2s1x1c1o0c0o1t1z1m9r1p1p1e1a1d1t9r9v0b1z1q0k0w2x1q9i8h8k0i0l0i8m8k8o8o8o8m0k1m2p0x1g0m9r8x2i4b3m3p3q3o0x1j3o3o3a3w0y0w1z2g2b2a2f1q3j3x3a0l1j4b2h2k2b2y9l9l2s2v3m1v0w0s0x9k0u0y9d1h0z0s1c0k3j0e1f3p3o2q1q9l0x3m2y2y3k4c3j3u2b3d3y2e3v1y2m1u1z8x0d4b4d3q3a0v0x1s2h2b1z1u2n3l3b3k1s0u9i0s0u9a1i0y0s1b0o0o7r1t3i3j3q3b2y2o从10000（64k）开始的位置。由于当时假设  
# system 模块最大长度不会超过80000（512k），也即其末端不会超过内存地址90000，
# 所以bootsect 会将自己移动到90000 开始的地方，并把setup 加载到它的后面。
# 下面这段程序的用途是再把整个system 模块移动到00000 位置，即把从10000 到8ffff
# 的内存数据块(512k)，整块地向内存低端移动了10000（64k）的位置。
	mov	$0x0000, %ax
	cld			# 'direction'=0, movs moves forward
do_move:
	mov	%ax, %es	# destination segment
	add	$0x1000, %ax
	cmp	$0x9000, %ax
	jz	end_move
	mov	%ax, %ds	# source segment
	sub	%di, %di
	sub	%si, %si
	mov 	$0x8000, %cx
	rep
	movsw
	jmp	do_move

# then we load the segment descriptors
# 此后，我们加载段描述符。从这里开始会遇到32 位保护模式的操作，因此需要Intel 32 位保护模式编程方面的知识了,
# lidt 指令用于加载中断描述符表(idt)寄存器，它的操作数是6 个字节，0-1 字节是描述符表的
# 长度值(字节)；2-5 字节是描述符表的32 位线性基地址（首地址），其形式参见下面
# 219-220 行和223-224 行的说明。中断描述符表中的每一个表项（8 字节）指出发生中断时
# 需要调用的代码的信息，与中断向量有些相似，但要包含更多的信息。
# lgdt 指令用于加载全局描述符表(gdt)寄存器，其操作数格式与lidt 指令的相同。全局描述符
# 表中的每个描述符项(8 字节)描述了保护模式下数据和代码段（块）的信息。其中包括段的
# 最大长度限制(16 位)、段的线性基址（32 位）、段的特权级、段是否在内存、读写许可以及
# 其它一些保护模式运行的标志。参见后面205-216 行。
end_move:
	mov	$SETUPSEG, %ax	# right, forgot this at first. didn't work :-)
	mov	%ax, %ds        #ds 指向本程序(setup)段。因为上面操作改变了ds的值
	lidt	idt_48		# load idt with 0,0 加载中断描述符表(idt)寄存器，idt_48 是6 字节操作数的位置
						# 前2 字节表示idt 表的限长，后4 字节表示idt 表所处的基地址
	lgdt	gdt_48		# load gdt with whatever appropriate 加载全局描述符表(gdt)寄存器，gdt_48 是6 字节操作数的位置

# that was painless, now we enable A20

	#call	empty_8042	# 8042 is the keyboard controller
	#mov	$0xD1, %al	# command write
	#out	%al, $0x64
	#call	empty_8042
	#mov	$0xDF, %al	# A20 on
	#out	%al, $0x60
	#call	empty_8042
	inb     $0x92, %al	# open A20 line(Fast Gate A20).
	orb     $0b00000010, %al
	outb    %al, $0x92

# well, that went ok, I hope. Now we have to reprogram the interrupts :-(
# we put them right after the intel-reserved hardware interrupts, at
# int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
# messed this up with the original PC, and they haven't been able to
# rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
# which is used for the internal hardware interrupts as well. We just
# have to reprogram the 8259's, and it isn't fun.
# 希望以上一切正常。现在我们必须重新对中断进行编程 我们将它们放在正好处于intel 保留的硬件中断后面，在int 20-2F。
# 在那里它们不会引起冲突。不幸的是IBM 在原PC 机中搞糟了，以后也没有纠正过来。 
# PC 机的bios 将中断放在了08-0f，这些中断也被用于内部硬件中断。
# 所以我们就必须重新对8259 中断控制器进行编程，这一点都没劲。

	# 11 表示初始化命令开始，是ICW1 命令字，表示边沿触发、多片8259 级连、最后要发送ICW4 命令字。
	mov	$0x11, %al		# initialization sequence(ICW1)
					# ICW4 needed(1),CASCADE mode,Level-triggered
	out	%al, $0x20		# send it to 8259A-1 发送到8259A 主芯片
	.word	0x00eb,0x00eb		# jmp $+2, jmp $+2  $ 表示当前指令的地址，两条跳转指令，跳到下一条指令，起延时作用
	out	%al, $0xA0		# and to 8259A-2 and to 8259A-2 ;// 再发送到8259A 从芯片。
	.word	0x00eb,0x00eb
	mov	$0x20, %al		# start of hardware int's (0x20)(ICW2) 
	out	%al, $0x21		# from 0x20-0x27 送主芯片ICW2 命令字，起始中断号，要送奇地址。
	.word	0x00eb,0x00eb
	mov	$0x28, %al		# start of hardware int's 2 (0x28)
	out	%al, $0xA1		# from 0x28-0x2F
	.word	0x00eb,0x00eb		#               IR 7654 3210
	mov	$0x04, %al		# 8259-1 is master(0000 0100) --\
	out	%al, $0x21		#				|
	.word	0x00eb,0x00eb		#			 INT	/
	mov	$0x02, %al		# 8259-2 is slave(       010 --> 2)
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	mov	$0x01, %al		# 8086 mode for both
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	mov	$0xFF, %al		# mask off all interrupts for now
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1

# well, that certainly wasn't fun :-(. Hopefully it works, and we don't
# need no steenking BIOS anyway (except for the initial loading :-).
# The BIOS-routine wants lots of unnecessary data, and it's less
# "interesting" anyway. This is how REAL programmers do it.
#
# Well, now's the time to actually move into protected mode. To make
# things as simple as possible, we do no register set-up or anything,
# we let the gnu-compiled 32-bit programs do that. We just jump to
# absolute address 0x00000, in 32-bit protected mode.
# 哼，上面这段当然没劲 ，希望这样能工作，而且我们也不再需要乏味的BIOS 了（除了初始的加载.。BIOS 子程序要求很多不必要的数据，
# 而且它一点都没趣。那是“真正”的程序员所做的事。
# 这里设置进入32 位保护模式运行。首先加载机器状态字(lmsw - Load Machine Status Word)，
# 也称控制寄存器CR0，其比特位0 置1 将导致CPU 工作在保护模式。

	#mov	$0x0001, %ax	# protected mode (PE) bit 保护模式比特位(PE)
	#lmsw	%ax		# This is it! 就这样加载机器状态字
	mov	%cr0, %eax	# get machine status(cr0|MSW)	
	bts	$0, %eax	# turn on the PE-bit 
	mov	%eax, %cr0	# protection enabled
				
				# segment-descriptor        (INDEX:TI:RPL)
	.equ	sel_cs0, 0x0008 # select for code segment 0 (  001:0 :00) 
	ljmp	$sel_cs0, $0	# jmp offset 0 of code segment 0 in gdt
	#此处相当与jump 0,8 跳到8段选择符，偏移量为0的地方开始执行，其中8为 001:0:00 
	# 最后2位的00是内核级，与之对应的是应用程序级 11 
	# 倒数第三位的0为GDT表，如果为1代表LDT表
	# 倒数第四位表示选择索引为1的段选择符
    # 跳转到head开始的地方开始执行

# This routine checks that the keyboard command queue is empty
# No timeout is used - if this hangs there is something wrong with
# the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb jmp $+2, jmp $+2 $ 表示当前指令的地址 是两个跳转指令的机器码(跳转到下一句)，相当于延时空操作。
	in	$0x64, %al	# 8042 status port 读AT 键盘控制器状态寄存器。
	test	$2, %al		# is input buffer full? 测试位2，输入缓冲器满？
	jnz	empty_8042	# yes - loop
	ret
# 全局描述符表开始处。描述符表由多个8 字节长的描述符项组成。
# 这里给出了3 个描述符项。第1 项无用，但须存在。第2 项是系统代码段
# 描述符（208-211 行），第3 项是系统数据段描述符(213-216 行)。每个描述符的具体含义参见列表后说明。
# 此时内核还未真正运行，还没有进程
gdt:
	.word	0,0,0,0		# dummy 第1 个描述符，不用。
# 这里在gdt 表中的偏移量为08，当加载代码段寄存器(段选择符)时，使用的是这个偏移值。--内核代码段
	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9A00		# code read/exec
	.word	0x00C0		# granularity=4096, 386
# 这里在gdt 表中的偏移量是10，当加载数据段寄存器(如ds 等)时，使用的是这个偏移值。--内核数据段
	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9200		# data read/write
	.word	0x00C0		# granularity=4096, 386

idt_48:
	.word	0			# idt limit=0
	.word	0,0			# idt base=0L

gdt_48:
	# 全局表长度为2k 字节，因为每8 字节组成一个段描述符项所以表中共可有256 项。
	.word	0x800			# gdt limit=2048, 256 GDT entries
	.word   512+gdt, 0x9		# gdt base = 0X9xxxx, 
	# 512+gdt is the real gdt after setup is moved to 0x9020 * 0x10
	# 4 个字节构成的内存线性地址：0009<<16 + 0200+gdt
	# 也即90200 + gdt(即在本程序段中的偏移地址，205 
.text
endtext:
.data
enddata:
.bss
endbss:
