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
# bootsect 引导程序是将system 模块读入到从10000（64k）开始的位置。由于当时假设  
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

end_move:
	mov	$SETUPSEG, %ax	# right, forgot this at first. didn't work :-)
	mov	%ax, %ds
	lidt	idt_48		# load idt with 0,0
	lgdt	gdt_48		# load gdt with whatever appropriate

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

	mov	$0x11, %al		# initialization sequence(ICW1)
					# ICW4 needed(1),CASCADE mode,Level-triggered
	out	%al, $0x20		# send it to 8259A-1
	.word	0x00eb,0x00eb		# jmp $+2, jmp $+2
	out	%al, $0xA0		# and to 8259A-2
	.word	0x00eb,0x00eb
	mov	$0x20, %al		# start of hardware int's (0x20)(ICW2)
	out	%al, $0x21		# from 0x20-0x27
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
	#mov	$0x0001, %ax	# protected mode (PE) bit
	#lmsw	%ax		# This is it!
	mov	%cr0, %eax	# get machine status(cr0|MSW)	
	bts	$0, %eax	# turn on the PE-bit 
	mov	%eax, %cr0	# protection enabled
				
				# segment-descriptor        (INDEX:TI:RPL)
	.equ	sel_cs0, 0x0008 # select for code segment 0 (  001:0 :00) 
	ljmp	$sel_cs0, $0	# jmp offset 0 of code segment 0 in gdt

# This routine checks that the keyboard command queue is empty
# No timeout is used - if this hangs there is something wrong with
# the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb
	in	$0x64, %al	# 8042 status port
	test	$2, %al		# is input buffer full?
	jnz	empty_8042	# yes - loop
	ret

gdt:
	.word	0,0,0,0		# dummy

	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9A00		# code read/exec
	.word	0x00C0		# granularity=4096, 386

	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9200		# data read/write
	.word	0x00C0		# granularity=4096, 386

idt_48:
	.word	0			# idt limit=0
	.word	0,0			# idt base=0L

gdt_48:
	.word	0x800			# gdt limit=2048, 256 GDT entries
	.word   512+gdt, 0x9		# gdt base = 0X9xxxx, 
	# 512+gdt is the real gdt after setup is moved to 0x9020 * 0x10
	
.text
endtext:
.data
enddata:
.bss
endbss:
