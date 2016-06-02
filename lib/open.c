/*
 *  linux/lib/open.c
 *
 *  (C) 1991  Linus Torvalds
 */

#define __LIBRARY__
#include <unistd.h>
#include <stdarg.h>

int open(const char * filename, int flag, ...)
{
	register int res;
	va_list arg;

	va_start(arg,flag);
	__asm__("int $0x80"  //调用linux系统终端服务，0x80
		:"=a" (res)      //返回值为res
		:"0" (__NR_open),"b" (filename),"c" (flag), //输入值为3个，
		"d" (va_arg(arg,int)));
	if (res>=0)  //如果返回值大于0，直接返回
		return res;
	errno = -res; //否则将error设置为返回值，返回-1
	return -1;
}
