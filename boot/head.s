/*
 *  linux/boot/head.s
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 *  head.s contains the 32-bit startup code.
 *
 * NOTE!!! Startup happens at absolute address 0x00000000, which is also where
 * the page directory will exist. The startup code will be overwritten by
 * the page directory.
 */
.text
.globl idt,gdt,pg_dir,tmp_floppy_area
pg_dir:
.globl startup_32
startup_32:
# 再次注意!!! 这里已经处于32 位运行模式，因此这里的$0x10 并不是把地址0x10 装入各
# 个段寄存器，它现在其实是全局段描述符表中的偏移值，或者更正确地说是一个描述符表
# 项的选择符。有关选择符的说明请参见setup.s 中的说明。这里$0x10 的含义是请求特权
# 级0(位0-1=0)、选择全局描述符表(位2=0)、选择表中第2 项(位3-15=2)。它正好指向表中
# 的数据段描述符项。（描述符的具体数值参见前面setup.s ）。下面代码的含义是：
# 置ds,es,fs,gs 中的选择符为setup.s 中构造的数据段（全局段描述符表的第2 项）=0x10，
# 并将堆栈放置在数据段中的_stack_start 数组内，然后使用新的中断描述符表和全局段
# 描述表.新的全局段描述表中初始内容与setup.s 中的完全一样。
	movl $0x10,%eax  # 重新设置段，将所有的段都指向0x10
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	mov %ax,%gs
	lss stack_start,%esp  #将esp指向stack_start的末尾 
	call setup_idt
	call setup_gdt
	movl $0x10,%eax		# reload all the segment registers
	mov %ax,%ds		# after changing gdt. CS was already
	mov %ax,%es		# reloaded in 'setup_gdt'
	mov %ax,%fs
	mov %ax,%gs
	lss stack_start,%esp
	xorl %eax,%eax
1:	incl %eax		# check that A20 really IS enabled
	movl %eax,0x000000	# loop forever if it isn't在实模式下地址会回卷即 0x000000和0x100000地址一样，读取值也应该一样
	cmpl %eax,0x100000
	je 1b  # '1b'表示向后(backward)跳转到标号1去,若是'5f'则表示向前(forward)跳转到标号5 去。
#
# NOTE! 486 should set bit 16, to check for write-protect in supervisor
# mode. Then it would be unnecessary with the "verify_area()"-calls.
# 486 users probably want to set the NE (#5) bit also, so as to use
# int 16 for math errors.
#
	movl %cr0,%eax		# check math chip
	andl $0x80000011,%eax	# Save PG,PE,ET
# "orl $0x10020,%eax" here for 486 might be good */
	orl $2,%eax		# set MP
	movl %eax,%cr0
	call check_x87
	jmp after_page_tables


# We depend on ET to be correct. This checks for 287/387.

check_x87:
	fninit
	fstsw %ax
	cmpb $0,%al
	je 1f			/* no coprocessor: have to set bits */
	movl %cr0,%eax
	xorl $6,%eax		/* reset MP, set EM */
	movl %eax,%cr0
	ret
.align 2
1:	.byte 0xDB,0xE4		/* fsetpm for 287, ignored by 387 */
	ret

#
# setup_idt
#
# sets up a idt with 256 entries pointing to
# ignore_int, interrupt gates. It then loads
# idt. Everything that wants to install itself
# in the idt-table may do so themselves. Interrupts
# are enabled elsewhere, when we can be relatively
# sure everything is ok. This routine will be over-
# written by the page tables.
# 将中断描述符表idt 设置成具有256 个项，并都指向ignore_int 中断门。然后加载
# 中断描述符表寄存器(用lidt 指令)。真正实用的中断门以后再安装。当我们在其它
# 地方认为一切都正常时再开启中断。该子程序将会被页表覆盖掉。
setup_idt:
	lea ignore_int,%edx
	movl $0x00080000,%eax # 将ignore_int 的有效地址（偏移值）值 edx 寄存器
	movw %dx,%ax		#  selector = 0x0008 = cs  将选择符0x0008 置入eax 的高16 位中。
	movw $0x8E00,%dx	# interrupt gate - dpl=0, present  
						# 偏移值的低16 位置入eax 的低16 位中。此时eax含有门描述符低4 字节的值。
	lea idt,%edi
	mov $256,%ecx
rp_sidt:
	movl %eax,(%edi)    # 将哑中断门描述符存入表中。
	movl %edx,4(%edi)
	addl $8,%edi        # edi 指向表中下一项。
	dec %ecx
	jne rp_sidt
	lidt idt_descr      #加载中断描述符表寄存器值
	ret
#
# setup_gdt
# This routines sets up a new gdt and loads it.
# Only two entries are currently built, the same
# ones that were built in init.s. The routine
# is VERY complicated at two whole lines, so this
# rather long comment is certainly needed :-).
# This routine will beoverwritten by the page tables.
# 这个子程序设置一个新的全局描述符表gdt，并加载。此时仅创建了两个表项，与前
# 面的一样。该子程序只有两行，“非常的”复杂，所以当然需要这么长的注释了:)。
setup_gdt:
	lgdt gdt_descr
	ret
# 
# I put the kernel page tables right after the page directory,
# using 4 of them to span 16 Mb of physical memory. People with
# more than 16MB will have to expand this.
# 
# Linus 将内核的内存页表直接放在页目录之后，使用了4 个表来寻址16 Mb 的物理内存。
# 如果你有多于16 Mb 的内存，就需要在这里进行扩充修改。
# 
# 每个页表长为4 Kb 字节，而每个页表项需要4 个字节，因此一个页表共可以存放1000 个，
# 表项如果一个表项寻址4 Kb 的地址空间，则一个页表就可以寻址4 Mb 的物理内存。页表项
# 的格式为：项的前0-11 位存放一些标志，如是否在内存中(P 位0)、读写许可(R/W 位1)、
# 普通用户还是超级用户使用(U/S 位2)、是否修改过(是否脏了)(D 位6)等；表项的位12-31 
# 是页框地址，用于指出一页内存的物理起始地址。
.org 0x1000
pg0:

.org 0x2000
pg1:

.org 0x3000
pg2:

.org 0x4000
pg3:

.org 0x5000  #定义下面的内存数据块从偏移0x5000 处开始

# tmp_floppy_area is used by the floppy-driver when DMA cannot
# reach to a buffer-block. It needs to be aligned, so that it isn't
# on a 64kB border.
# 当DMA（直接存储器访问）不能访问缓冲块时，下面的tmp_floppy_area 内存块
# 就可供软盘驱动程序使用。其地址需要对齐调整，这样就不会跨越64kB 边界。

tmp_floppy_area:
	.fill 1024,1,0  # 保留1024 项，每项1 字节，填充数值0  ：： db 1024 dup(0)	

# 下面这几个入栈操作(pushl)用于为调用/init/main.c 程序和返回作准备。
# 前面3 个入栈指令不知道作什么用的，也许是Linus 用于在调试时能看清机器码用的.。
# 139 行的入栈操作是模拟调用main.c 程序时首先将返回地址入栈的操作，所以如果
# main.c 程序真的退出时，就会返回到这里的标号L6 处继续执行下去，也即死循环。
# 140 行将main.c 的地址压入堆栈，这样，在设置分页处理（setup_paging）结束后
# 执行'ret'返回指令时就会将main.c 程序的地址弹出堆栈，并去执行main.c 程序去了。

after_page_tables:
	pushl $0		# These are the parameters to main :-)
	pushl $0
	pushl $0
	pushl $L6		# return address for main, if it decides to.
	pushl $main
	jmp setup_paging
L6:
	jmp L6			# main should never return here, but
				# just in case, we know what happens. 

# This is the default interrupt "handler" :-) 
int_msg:
	.asciz "Unknown interrupt\n\r" # 定义字符串“未知中断(回车换行)”。
.align 2 						   # 按4 字节方式对齐内存地址
ignore_int:
	pushl %eax
	pushl %ecx
	pushl %edx
	push %ds    # 这里请注意！！ds,es,fs,gs 等虽然是16 位的寄存器，但入栈后
	push %es    # 仍然会以32 位的形式入栈，也即需要占用4 个字节的堆栈空间。
	push %fs
	movl $0x10,%eax  # 置段选择符（使ds,es,fs 指向gdt 表中的数据段）。
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	pushl $int_msg # 把调用printk 函数的参数指针（地址）入栈。
	call printk # 该函数在/kernel/printk.c 中。 '_printk'是printk 编译后模块中的内部表示法。
	popl %eax
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret       # 中断返回（把中断调用时压入栈的CPU 标志寄存器（32 位）值也弹出）


#
# Setup_paging
#
# This routine sets up paging by setting the page bit
# in cr0. The page tables are set up, identity-mapping
# the first 16MB. The pager assumes that no illegal
# addresses are produced (ie >4Mb on a 4Mb machine).
#
# NOTE! Although all physical memory should be identity
# mapped by this routine, only the kernel page functions
# use the >1Mb addresses directly. All "normal" functions
# use just the lower 1Mb, or the local data space, which
# will be mapped to some other place - mm keeps track of
# that.
#
# For those with more memory than 16 Mb - tough luck. I've
# not got it, why should you :-) The source is here. Change
# it. (Seriously - it shouldn't be too difficult. Mostly
# change some constants etc. I left it at 16Mb, as my machine
# even cannot be extended past that (ok, but it was cheap :-)
# I've tried to show which constants to change by having
# some kind of marker at them (search for "16Mb"), but I
# won't guarantee that's all :-( )
#
# 这个子程序通过设置控制寄存器cr0 的标志（PG 位31）来启动对内存的分页处理
# 功能，并设置各个页表项的内容，以恒等映射前16 MB 的物理内存。分页器假定
# 不会产生非法的地址映射（也即在只有4Mb 的机器上设置出大于4Mb 的内存地址）。
# 注意！尽管所有的物理地址都应该由这个子程序进行恒等映射，但只有内核页面管
# 理函数能直接使用>1Mb 的地址。所有“一般”函数仅使用低于1Mb 的地址空间，或
# 者是使用局部数据空间，地址空间将被映射到其它一些地方去-- mm(内存管理程序)
# 会管理这些事的。
# 对于那些有多于16Mb 内存的家伙- 太幸运了，我还没有，为什么你会有:-)。代码就
# 在这里，对它进行修改吧。（实际上，这并不太困难的。通常只需修改一些常数等。
# 我把它设置为16Mb，因为我的机器再怎么扩充甚至不能超过这个界限（当然，我的机 
# 器很便宜的:-)）。我已经通过设置某类标志来给出需要改动的地方（搜索“16Mb”），
# 但我不能保证作这些改动就行了 :-( )

.align 2   # 按4 字节方式对齐内存地址边界。
setup_paging:    #首先对5 页内存（1 页目录+ 4 页页表）清零
	movl $1024*5,%ecx		/* 5 pages - pg_dir+4 page tables */
	xorl %eax,%eax
	xorl %edi,%edi			/* pg_dir is at 0x000 */
	cld;rep;stosl
# 下面4 句设置页目录中的项，我们共有4 个页表所以只需设置4 项。
# 页目录项的结构与页表中项的结构一样，4 个字节为1 项。参见上面的说明。
# "$pg0+7"表示：0x00001007，是页目录表中的第1 项。
# 则第1 个页表所在的地址= 0x00001007 & 0xfffff000 = 0x1000；第1 个页表
# 的属性标志= 0x00001007 & 0x00000fff = 0x07，表示该页存在、用户可读写。	
	movl $pg0+7,pg_dir		/* set present bit/user r/w */
	movl $pg1+7,pg_dir+4		/*  --------- " " --------- */
	movl $pg2+7,pg_dir+8		/*  --------- " " --------- */
	movl $pg3+7,pg_dir+12		/*  --------- " " --------- */

# 下面6 行填写4 个页表中所有项的内容，共有：4(页表)*1024(项/页表)=4096 项(0 - 0xfff)，
# 也即能映射物理内存4096*4Kb = 16Mb。
# 每项的内容是：当前项所映射的物理内存地址+ 该页的标志（这里均为7）。
# 使用的方法是从最后一个页表的最后一项开始按倒退顺序填写。一个页表的最后一项
# 在页表中的位置是1023*4 = 4092。因此最后一页的最后一项的位置就是$pg3+4092。

	movl $pg3+4092,%edi     # di -> 最后一页的最后一项
	movl $0xfff007,%eax		#  16Mb - 4096 + 7 (r/w user,p)  最后1 项对应物理内存页面的地址是0xfff000，加上属性标志7，即为0xfff007.
	std                     # 方向位置位，edi 值递减(4 字节)
1:	stosl			/* fill pages backwards - more efficient :-) */
	subl $0x1000,%eax #每填写好一项，物理地址值减0x1000
	jge 1b            #如果小于0 则说明全添写好了
	cld
	xorl %eax,%eax		/* pg_dir is at 0x0000 */
	movl %eax,%cr3		/* cr3 - page directory start */
	movl %cr0,%eax      # 设置启动使用分页处理（cr0 的PG 标志，位31）
	orl $0x80000000,%eax #添上PG 标志
	movl %eax,%cr0		/* set paging (PG) bit */
	ret			/* this also flushes prefetch-queue */

# 在改变分页处理标志后要求使用转移指令刷新预取指令队列，这里用的是返回指令ret。
# 该返回指令的另一个作用是将堆栈中的main 程序的地址弹出，并开始运行/init/main.c 
# 程序。本程序到此真正结束了。

.align 2    # 按4 字节方式对齐内存地址边界
.word 0
idt_descr:  # 下面两行是lidt 指令的6 字节操作数：长度，基址。
	.word 256*8-1		# idt contains 256 entries
	.long idt
.align 2
.word 0
gdt_descr:
	.word 256*8-1		# so does gdt (not that that's any
	.long gdt		# magic number, but it works for me :^)

	.align 8
idt:	.fill 256,8,0		# idt is uninitialized

gdt:	.quad 0x0000000000000000	# NULL descriptor 
	.quad 0x00c09a0000000fff	# 16Mb 
	.quad 0x00c0920000000fff	# 16Mb 
	.quad 0x0000000000000000	# TEMPORARY - don't use 
	.fill 252,8,0			# space for LDT's and TSS's etc 
