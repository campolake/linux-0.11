//// 切换到用户模式运行。
// 该函数利用iret 指令实现从内核模式切换到用户模式（初始任务0）。
#define move_to_user_mode() \
_asm { \
	_asm mov eax,esp /* 保存堆栈指针esp 到eax 寄存器中。*/\
	_asm push 00000017h /* 首先将堆栈段选择符(SS)入栈。*/\
	_asm push eax /* 然后将保存的堆栈指针值(esp)入栈。*/\
	_asm pushfd /* 将标志寄存器(eflags)内容入栈。*/\
	_asm push 0000000fh /* 将内核代码段选择符(cs)入栈。*/\
	_asm push offset l1 /* 将下面标号l1 的偏移地址(eip)入栈。*/\
	_asm iretd /* 执行中断返回指令，则会跳转到下面标号1 处。*/\
_asm l1: mov eax,17h /* 此时开始执行任务0，*/\
	_asm mov ds,ax /* 初始化段寄存器指向本局部表的数据段。*/\
	_asm mov es,ax \
	_asm mov fs,ax \
	_asm mov gs,ax \
}
/*
__asm__ ( "movl %%esp,%%eax\n\t" \	
"pushl $0x17\n\t" \		
  "pushl %%eax\n\t" \		
  "pushfl\n\t" \		
  "pushl $0x0f\n\t" \		
  "pushl $1f\n\t" \		
  "iret\n" \			
  "1:\tmovl $0x17,%%eax\n\t" \	
  "movw %%ax,%%ds\n\t" \	// 初始化段寄存器指向本局部表的数据段。
"movw %%ax,%%es\n\t" "movw %%ax,%%fs\n\t" "movw %%ax,%%gs":::"ax")
*/
#define sti() _asm{ _asm sti }// 开中断嵌入汇编宏函数。
//__asm__ ( "sti"::)	
#define cli() _asm{ _asm cli }// 关中断。
//__asm__ ( "cli"::)	
#define nop() _asm{ _asm nop }// 空操作。
//__asm__ ( "nop"::)	
#define iret() _asm{ _asm iretd }// 中断返回。
//__asm__ ( "iret"::)	

//// 设置门描述符宏函数。
// 参数：gate_addr -描述符地址；type -描述符中类型域值；dpl -描述符特权层值；addr -偏移地址。
// %0 - (由dpl,type 组合成的类型标志字)；%1 - (描述符低4 字节地址)；
// %2 - (描述符高4 字节地址)；%3 - edx(程序偏移地址addr)；%4 - eax(高字中含有段选择符)。
void _inline _set_gate(unsigned long *gate_addr, \
					   unsigned short type, \
					   unsigned short dpl, \
					   unsigned long addr) 
{// c语句和汇编语句都可以通过
	gate_addr[0] = 0x00080000 + (addr & 0xffff);
	gate_addr[1] = 0x8000 + (dpl << 13) + (type << 8) + (addr & 0xffff0000);
/*	unsigned short tmp = 0x8000 + (dpl << 13) + (type << 8);
	_asm mov eax,00080000h ;
	_asm mov edx,addr ;
	_asm mov ax,dx ;// 将偏移地址低字与段选择符组合成描述符低4 字节(eax)。
	_asm mov dx,tmp ;// 将类型标志字与偏移高字组合成描述符高4 字节(edx)。
	_asm mov ebx,gate_addr
	_asm mov [ebx],eax ;// 分别设置门描述符的低4 字节和高4 字节。
	_asm mov [ebx+4],edx ;*/
}
/*
__asm__ ( "movw %%dx,%%ax\n\t" \	
  "movw %0,%%dx\n\t" \		
  "movl %%eax,%1\n\t" \		
"movl %%edx,%2":
:"i" ((short) (0x8000 + (dpl << 13) + (type << 8))),
  "o" (*((char *) (gate_addr))),
  "o" (*(4 + (char *) (gate_addr))), "d" ((char *) (addr)), "a" (0x00080000))
*/

//// 设置中断门函数。
// 参数：n - 中断号；addr - 中断程序偏移地址。
// &idt[n]对应中断号在中断描述符表中的偏移值；中断描述符的类型是14，特权级是0。
#define set_intr_gate(n,addr) \
_set_gate((unsigned long*)(&(idt[n])),14,0,(unsigned long)addr)
//// 设置陷阱门函数。
// 参数：n - 中断号；addr - 中断程序偏移地址。
// &idt[n]对应中断号在中断描述符表中的偏移值；中断描述符的类型是15，特权级是0。
#define set_trap_gate(n,addr) \
_set_gate((unsigned long*)(&(idt[n])),15,0,(unsigned long)addr)
//// 设置系统调用门函数。
// 参数：n - 中断号；addr - 中断程序偏移地址。
// &idt[n]对应中断号在中断描述符表中的偏移值；中断描述符的类型是15，特权级是3。
#define set_system_gate(n,addr) \
_set_gate((unsigned long*)(&(idt[n])),15,3,(unsigned long)addr)
//// 设置段描述符函数。
// 参数：gate_addr -描述符地址；type -描述符中类型域值；dpl -描述符特权层值；
// base - 段的基地址；limit - 段限长。（参见段描述符的格式）
#define _set_seg_desc(gate_addr,type,dpl,base,limit) {\
*(gate_addr) = ((base) & 0xff000000) | \
				(((base) & 0x00ff0000) >> 16) | \
				((limit) & 0xf0000) | \
				((dpl) << 13) | \
				(0x00408000) | \
				((type) << 8);/* 描述符低4 字节。*/\
*((gate_addr) + 1) = (((base) & 0x0000ffff) << 16) | \
				((limit) & 0x0ffff);/* 描述符高4 字节。*/ \
}

//// 在全局表中设置任务状态段/局部表描述符。
// 参数：n - 在全局表中描述符项n 所对应的地址；addr - 状态段/局部表所在内存的基地址。
// tp - 描述符中的标志类型字节。
// %0 - eax(地址addr)；%1 - (描述符项n 的地址)；%2 - (描述符项n 的地址偏移2 处)；
// %3 - (描述符项n 的地址偏移4 处)；%4 - (描述符项n 的地址偏移5 处)；
// %5 - (描述符项n 的地址偏移6 处)；%6 - (描述符项n 的地址偏移7 处)；
extern _inline void _set_tssldt_desc(unsigned short *n,unsigned long addr,char tp) 
{ 
/*	n[0] = 104;
	n[1] = addr;
	n[2] = addr >> 16;
	((char*)n)[7] = ((char*)n)[5];
	((char*)n)[5] = tp;
	((char*)n)[6] = 0;*/
	_asm mov ebx,n
	_asm mov ax,104 
	_asm mov word ptr [ebx],ax // 将TSS 长度放入描述符长度域(第0-1 字节)。
	_asm mov eax,addr 
	_asm mov word ptr [ebx+2],ax // 将基地址的低字放入描述符第2-3 字节。
	_asm ror eax,16 // 将基地址高字移入ax 中。
	_asm mov byte ptr [ebx+4],al // 将基地址高字中低字节移入描述符第4 字节。
	_asm mov al,tp
	_asm mov byte ptr [ebx+5],al // 将标志类型字节移入描述符的第5 字节。
	_asm mov al,0 
	_asm mov byte ptr [ebx+6],al // 描述符的第6 字节置0。
	_asm mov byte ptr [ebx+7],ah // 将基地址高字中高字节移入描述符第7 字节。
	_asm ror eax,16 // eax 清零。
}
/*
__asm__ ( "movw $104,%1\n\t" \	
"movw %%ax,%2\n\t" \		
  "rorl $16,%%eax\n\t" \	
  "movb %%al,%3\n\t" \		
  "movb $" type ",%4\n\t" \	
  "movb $0x00,%5\n\t" \		
  "movb %%ah,%6\n\t" \		
  "rorl $16,%%eax" \		
  ::"a" (addr), "m" (*(n)), "m" (*(n + 2)), "m" (*(n + 4)),
  "m" (*(n + 5)), "m" (*(n + 6)), "m" (*(n + 7)))
*/
//// 在全局表中设置任务状态段描述符。
// n - 是该描述符的指针；addr - 是描述符中的基地址值。任务状态段描述符的类型是0x89。
#define set_tss_desc(n,addr) \
_set_tssldt_desc((unsigned short*)(n),(unsigned long)(addr), (char)0x89)
//// 在全局表中设置局部表描述符。
// n - 是该描述符的指针；addr - 是描述符中的基地址值。局部表描述符的类型是0x82。
#define set_ldt_desc(n,addr) \
_set_tssldt_desc((unsigned short*)(n),(unsigned long)(addr), (char)0x82)
