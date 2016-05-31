/* passed
 *  linux/fs/bitmap.c
 *
 *  (C) 1991  Linus Torvalds
 */
#include <set_seg.h>

/* bitmap.c 程序含有处理i 节点和磁盘块位图的代码 */

// 字符串头文件。主要定义了一些有关字符串操作的嵌入函数。
// 主要使用了其中的memset()函数。
#include <string.h>
// 调度程序头文件，定义了任务结构task_struct、初始任务0 的数据，
// 还有一些有关描述符参数设置和获取的嵌入式汇编函数宏语句。
#include <linux/sched.h>
// 内核头文件。含有一些内核常用函数的原形定义。
#include <linux/kernel.h>

//// 将指定地址(addr)处的一块内存清零。嵌入汇编程序宏。
// 输入：eax = 0，ecx = 数据块大小BLOCK_SIZE/4，edi = addr。
extern _inline void clear_block(char *addr)
{_asm{
	pushf
	mov edi,addr
	mov ecx,BLOCK_SIZE/4
	xor eax,eax
	cld
	rep stosd
	popf
}}
//#define clear_block(addr) \
//__asm__("cld\n\t" \  /*清方向位。*/
//	"rep\n\t" \  /*重复执行存储数据（0）。*/
//	"stosl" \
//	::"a" (0),"c" (BLOCK_SIZE/4),"D" ((long) (addr)):"cx","di")

//// 置位指定地址开始的第nr 个位偏移处的比特位(nr 可以大于32！)。返回原比特位（0 或1）。
// 输入：%0 - eax（返回值)，%1 - eax(0)；%2 - nr，位偏移值；%3 - (addr)，addr 的内容。
extern _inline int set_bit(unsigned long nr,char* addr)
{
//	volatile register int __res;
	_asm{
		xor eax,eax
		mov ebx,nr
		mov edx,addr
		bts [edx],ebx
		setb al
//		mov __res,eax
	}
//	return __res;
}
//#define set_bit(nr,addr) ({\
//register int res __asm__("ax"); \
//__asm__ __volatile__("btsl %2,%3\n\tsetb %%al": \
//"=a" (res):"0" (0),"r" (nr),"m" (*(addr))); \
//res;})

//// 复位指定地址开始的第nr 位偏移处的比特位。返回原比特位的反码（1 或0）。
// 输入：%0 - eax（返回值)，%1 - eax(0)；%2 - nr，位偏移值；%3 - (addr)，addr 的内容。
extern _inline int clear_bit(unsigned long nr,char* addr)
{
//	volatile register int __res;
	_asm{
		xor eax,eax
		mov ebx,nr
		mov edx,addr
		btr [edx],ebx
		setnb al
//		mov __res,eax
	}
//	return __res;
}
//#define clear_bit(nr,addr) ({\
//register int res __asm__("ax"); \
//__asm__ __volatile__("btrl %2,%3\n\tsetnb %%al": \
//"=a" (res):"0" (0),"r" (nr),"m" (*(addr))); \
//res;})

//// 从addr 开始寻找第1 个0 值比特位。
// 输入：%0 - ecx(返回值)；%1 - ecx(0)；%2 - esi(addr)。
// 在addr 指定地址开始的位图中寻找第1 个是0 的比特位，并将其距离addr 的比特位偏移值返回。
extern _inline int find_first_zero(char *addr)
{
//	int __res;
	_asm{
		pushf
		xor ecx,ecx
		mov esi,addr
		cld   /*清方向位。*/
	l1: lodsd   /*取[esi] -> eax。*/
		not eax   /*eax 中每位取反。*/
		bsf edx,eax   /*从位0 扫描eax 中是1 的第1 个位，其偏移值 -> edx。*/
		je l2   /*如果eax 中全是0，则向前跳转到标号2 处(40 行)。*/
		add ecx,edx   /*偏移值加入ecx(ecx 中是位图中首个是0 的比特位的偏移值)*/
		jmp l3   /*向前跳转到标号3 处（结束）。*/
	l2: add ecx,32   /*没有找到0 比特位，则将ecx 加上1 个长字的位偏移量32。*/
		cmp ecx,8192   /*已经扫描了8192 位（1024 字节）了吗？*/
		jl l1  /*若还没有扫描完1 块数据，则向前跳转到标号1 处，继续。*/
//	l3: mov __res,ecx  /*结束。此时ecx 中是位偏移量。*/
	l3: mov eax,ecx
		popf
	}
//	return __res;
}
/*#define find_first_zero(addr) ({ \
int __res; \
__asm__("cld\n" \
	"1:\tlodsl\n\t" \
	"notl %%eax\n\t" \
	"bsfl %%eax,%%edx\n\t" \
	"je 2f\n\t" \
	"addl %%edx,%%ecx\n\t" \
	"jmp 3f\n" \
	"2:\taddl $32,%%ecx\n\t" \
	"cmpl $8192,%%ecx\n\t" \
	"jl 1b\n" \ 
	"3:" \ 
	:"=c" (__res):"c" (0),"S" (addr):"ax","dx","si"); \
__res;})*/

//// 释放设备dev 上数据区中的逻辑块block。
// 复位指定逻辑块block 的逻辑块位图比特位。
// 参数：dev 是设备号，block 是逻辑块号（盘块号）。
void free_block(int dev, int block)
{
	struct super_block * sb;
	struct buffer_head * bh;

// 取指定设备dev 的超级块，如果指定设备不存在，则出错死机。
	if (!(sb = get_super(dev)))
		panic("trying to free block on nonexistent device");
// 若逻辑块号小于首个逻辑块号或者大于设备上总逻辑块数，则出错，死机。
	if (block < sb->s_firstdatazone || block >= sb->s_nzones)
		panic("trying to free block not in datazone");
// 从hash 表中寻找该块数据。若找到了则判断其有效性，并清已修改和更新标志，释放该数据块。
// 该段代码的主要用途是如果该逻辑块当前存在于高速缓冲中，就释放对应的缓冲块。
	bh = get_hash_table(dev,block);
	if (bh) {
		if (bh->b_count != 1) {
			printk("trying to free block (%04x:%d), count=%d\n",
				dev,block,bh->b_count);
			return;
		}
		bh->b_dirt=0;		// 复位脏（已修改）标志位。
		bh->b_uptodate=0;	// 复位更新标志。
		brelse(bh);
	}
// 计算block 在数据区开始算起的数据逻辑块号（从1 开始计数）。然后对逻辑块(区块)位图进行操作，
// 复位对应的比特位。若对应比特位原来即是0，则出错，死机。
	block -= sb->s_firstdatazone - 1 ;
	if (clear_bit(block&8191,sb->s_zmap[block/8192]->b_data)) {
		printk("block (%04x:%d) ",dev,block+sb->s_firstdatazone-1);
		panic("free_block: bit already cleared");
	}
	// 置相应逻辑块位图所在缓冲区已修改标志。
	sb->s_zmap[block/8192]->b_dirt = 1;
}

////向设备dev 申请一个逻辑块（盘块，区块）。返回逻辑块号（盘块号）。
// 置位指定逻辑块block 的逻辑块位图比特位。
int new_block(int dev)
{
	struct buffer_head * bh;
	struct super_block * sb;
	int i,j;

// 从设备dev 取超级块，如果指定设备不存在，则出错死机。
	if (!(sb = get_super(dev)))
		panic("trying to get new block from nonexistant device");
// 扫描逻辑块位图，寻找首个0 比特位，寻找空闲逻辑块，获取放置该逻辑块的块号。
	j = 8192;
	for (i=0 ; i<8 ; i++)
		if (bh=sb->s_zmap[i])
			if ((j=find_first_zero(bh->b_data))<8192)
				break;
// 如果全部扫描完还没找到(i>=8 或j>=8192)或者位图所在的缓冲块无效(bh=NULL)则返回0，
// 退出（没有空闲逻辑块）。
	if (i>=8 || !bh || j>=8192)
		return 0;
// 设置新逻辑块对应逻辑块位图中的比特位，若对应比特位已经置位，则出错，死机。
	if (set_bit(j,bh->b_data))
		panic("new_block: bit already set");
// 置对应缓冲区块的已修改标志。如果新逻辑块大于该设备上的总逻辑块数，则说明指定逻辑块在
// 对应设备上不存在。申请失败，返回0，退出。
	bh->b_dirt = 1;
	j += i*8192 + sb->s_firstdatazone-1;
	if (j >= sb->s_nzones)
		return 0;
// 读取设备上的该新逻辑块数据（验证）。如果失败则死机。
	if (!(bh=getblk(dev,j)))
		panic("new_block: cannot get block");
// 新块的引用计数应为1。否则死机。
	if (bh->b_count != 1)
		panic("new block: count is != 1");
// 将该新逻辑块清零，并置位更新标志和已修改标志。然后释放对应缓冲区，返回逻辑块号。
	clear_block(bh->b_data);
	bh->b_uptodate = 1;
	bh->b_dirt = 1;
	brelse(bh);
	return j;
}

//// 释放指定的i 节点。
// 复位对应i 节点位图比特位。
void free_inode(struct m_inode * inode)
{
	struct super_block * sb;
	struct buffer_head * bh;

	// 如果i 节点指针=NULL，则退出。
	if (!inode)
		return;
// 如果i 节点上的设备号字段为0，说明该节点无用，则用0 清空对应i 节点所占内存区，并返回。
	if (!inode->i_dev) {
		memset(inode,0,sizeof(*inode));
		return;
	}
// 如果此i 节点还有其它程序引用，则不能释放，说明内核有问题，死机。
	if (inode->i_count>1) {
		printk("trying to free inode with count=%d\n",inode->i_count);
		panic("free_inode");
	}
// 如果文件目录项连接数不为0，则表示还有其它文件目录项在使用该节点，
// 不应释放，而应该放回等。
	if (inode->i_nlinks)
		panic("trying to free inode with links");
// 取i 节点所在设备的超级块，测试设备是否存在。
	if (!(sb = get_super(inode->i_dev)))
		panic("trying to free inode on nonexistent device");
// 如果i 节点号=0 或大于该设备上i 节点总数，则出错（0 号i 节点保留没有使用）。
	if (inode->i_num < 1 || inode->i_num > sb->s_ninodes)
		panic("trying to free inode 0 or nonexistant inode");
// 如果该i 节点对应的节点位图不存在，则出错。
	if (!(bh=sb->s_imap[inode->i_num>>13]))
		panic("nonexistent imap in superblock");
// 复位i 节点对应的节点位图中的比特位，如果该比特位已经等于0，则出错。
	if (clear_bit(inode->i_num&8191,bh->b_data))
		printk("free_inode: bit already cleared.\n\r");
// 置i 节点位图所在缓冲区已修改标志，并清空该i 节点结构所占内存区。
	bh->b_dirt = 1;
	memset(inode,0,sizeof(*inode));
}

//// 为设备dev 建立一个新i 节点。返回该新i 节点的指针。
// 在内存i 节点表中获取一个空闲i 节点表项，并从i 节点位图中找一个空闲i 节点。
struct m_inode * new_inode(int dev)
{
	struct m_inode * inode;
	struct super_block * sb;
	struct buffer_head * bh;
	int i,j;

// 从内存i 节点表(inode_table)中获取一个空闲i 节点项(inode)。
	if (!(inode=get_empty_inode()))
		return NULL;
// 读取指定设备的超级块结构。
	if (!(sb = get_super(dev)))
		panic("new_inode with unknown device");
// 扫描i 节点位图，寻找首个0 比特位，寻找空闲节点，获取放置该i 节点的节点号。
	j = 8192;
	for (i=0 ; i<8 ; i++)
		if (bh=sb->s_imap[i])
			if ((j=find_first_zero(bh->b_data))<8192)
				break;
// 如果全部扫描完还没找到，或者位图所在的缓冲块无效(bh=NULL)则返回0，退出（没有空闲i 节点）。
	if (!bh || j >= 8192 || j+i*8192 > sb->s_ninodes) {
		iput(inode);
		return NULL;
	}
// 置位对应新i 节点的i 节点位图相应比特位，如果已经置位，则出错。
	if (set_bit(j,bh->b_data))
		panic("new_inode: bit already set");
// 置i 节点位图所在缓冲区已修改标志。
	bh->b_dirt = 1;
// 初始化该i 节点结构。
	inode->i_count=1;		// 引用计数。
	inode->i_nlinks=1;		// 文件目录项链接数。
	inode->i_dev=dev;		// i 节点所在的设备号。
	inode->i_uid=current->euid;		// i 节点所属用户id。
	inode->i_gid=current->egid;		// 组id。
	inode->i_dirt=1;			// 已修改标志置位。
	inode->i_num = j + i*8192;	// 对应设备中的i 节点号。
	inode->i_mtime = inode->i_atime = inode->i_ctime = CURRENT_TIME;	// 设置时间。
	return inode;	// 返回该i 节点指针。
}

/*
	本程序的功能和作用即简单又清晰，主要用于对i 节点位图和逻辑块位图进行释放和
占用处理。操作i 节点位图的函数是free_inode()和new_inode()，操作逻辑块位图的函数
是free_block()和new_block()。
	函数free_block()用于释放指定设备dev 上数据区中的逻辑块block。具体操作是复位
指定逻辑块block对应逻辑块位图中的比特位。它首先取指定设备dev 的超级块，并根据超
级块上给出的设备数据逻辑块的范围，判断逻辑块号block 的有效性。然后在高速缓冲区中
进行查找，看看指定的逻辑块现在是否正在高速缓冲区中，若是，则将对应的缓冲块释放掉。
接着计算block 从数据区开始算起的数据逻辑块号（从1开始计数），并对逻辑块(区段)位图
进行操作，复位对应的比特位。最后根据逻辑块号设置相应逻辑块位图在缓冲区中对应的
缓冲块的已修改标志。
	函数new_block()用于向设备dev 申请一个逻辑块，返回逻辑块号。并置位指定逻辑块
block 对应的逻辑块位图比特位。它首先取指定设备dev 的超级块。然后对整个逻辑块位图
进行搜索，寻找首个是0 的比特位。若没有找到，则说明盘设备空间已用完，返回0。否则
将该比特位置为1，表示占用对应的数据逻辑块。并将该比特位所在缓冲块的已修改标志置位。
接着计算出数据逻辑块的盘块号，并在高速缓冲区中申请相应的缓冲块，并把该缓冲块清零。
然后设置该缓冲块的已更新和已修改标志。最后释放该缓冲块，以便其它程序使用，并返回
盘块号（逻辑块号）。
	函数free_inode()用于释放指定的i 节点，并复位对应的i 节点位图比特位；new_inode()
用于为设备dev建立一个新i 节点。返回该新i 节点的指针。主要操作过程是在内存i 节点表
中获取一个空闲i 节点表项，并从i 节点位图中找一个空闲i 节点。这两个函数的处理过程
与上述两个函数类似，因此这里就不用再赘述。
*/
