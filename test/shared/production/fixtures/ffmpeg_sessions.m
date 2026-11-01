// Execute multiple commands on the same native thread so FFmpegKit's
// thread-local option state is reused, as it is by the app's worker pool.
#import <Foundation/Foundation.h>
#import <ffmpegkit/FFmpegKit.h>
#import <ffmpegkit/FFmpegKitConfig.h>
#import <ffmpegkit/ReturnCode.h>

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc != 2) {
      return 2;
    }
    NSError *error = nil;
    NSData *data = [[NSString stringWithUTF8String:argv[1]]
        dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *commands = [NSJSONSerialization JSONObjectWithData:data
        options:0 error:&error];
    if (error || ![commands isKindOfClass:[NSArray class]]) {
      return 2;
    }
    [FFmpegKitConfig disableRedirection];
    NSMutableArray *codes = [NSMutableArray array];
    for (NSArray *arguments in commands) {
      FFmpegSession *session = [FFmpegKit executeWithArguments:arguments];
      ReturnCode *code = [session getReturnCode];
      [codes addObject:code ? @([code getValue]) : [NSNull null]];
    }
    NSData *output = [NSJSONSerialization dataWithJSONObject:codes
        options:0 error:&error];
    if (error) {
      return 2;
    }
    fwrite(output.bytes, 1, output.length, stdout);
    fputc('\n', stdout);
  }
  return 0;
}
