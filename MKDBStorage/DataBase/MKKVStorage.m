//
//  MKKVStorage.m
//  Basic
//
//  Created by mikazheng on 2019/11/29.
//  Copyright © 2019 zhengmiaokai. All rights reserved.
//

#import "MKKVStorage.h"
#import <MKUtils/MarcoConstant.h>

#define kMKKVDbName  @"KVStorage.db"

#define LOCK(...) dispatch_semaphore_wait(self.lock, DISPATCH_TIME_FOREVER); \
__VA_ARGS__; \
dispatch_semaphore_signal(self.lock);

/* KV-Model */
@interface MKKeyValueDBItem : MKDBModel

@property (nonatomic, copy) NSString *key;

@property (nonatomic, copy) NSString *value;

+ (instancetype)itemWithValue:(NSString *)value forKey:(NSString *)key;

+ (instancetype)itemWithResult:(FMResultSet *)result;

@end

@interface MKKVStorage ()

@property (nonatomic, strong) NSMutableDictionary *storageItems;

@property (nonatomic, strong) dispatch_semaphore_t lock;

@end

@implementation MKKVStorage

+ (instancetype)sharedInstance {
    static MKKVStorage *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^ {
        dispatch_queue_t gcd_queue = dispatch_queue_create("com.MKKVStorage.queue", NULL);
        sharedInstance = [[self alloc] initWithDbName:kMKKVDbName gcdQueue:gcd_queue];
    });
    return sharedInstance;
}

- (instancetype)initWithDbName:(NSString *)dbName gcdQueue:(dispatch_queue_t)gcdQueue {
    self = [super initWithDbName:dbName gcdQueue:gcdQueue];
    if (self) {
        self.storageItems = [[NSMutableDictionary alloc] init];
        self.lock = dispatch_semaphore_create(1);
    }
    return self;
}

- (void)onLoad {
    [self inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if ([db tableExists:self.tableName] == NO) {
            [db creatWithTableName:self.tableName dataBaseModel:[MKKeyValueDBItem class]];
        }
    } isAsync:YES completion:nil];
}

- (void)creatTableWithName:(NSString *)tableName {
    [self inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if ([db tableExists:tableName] == NO) {
            [db creatWithTableName:tableName dataBaseModel:[MKKeyValueDBItem class]];
        }
    } isAsync:YES completion:nil];
}

- (void)getValueForKey:(NSString *)key completion:(MKDBCompletionHandler)completionHandler {
    [self getValueForKey:key tableName:nil completion:completionHandler];
}

- (void)getValueForKey:(NSString *)key tableName:(NSString *)tableName completion:(MKDBCompletionHandler)completionHandler {
    LOCK(MKKeyValueDBItem *_storageItem = [_storageItems objectForKey:key]);
    
    if (_storageItem) {
        if (completionHandler) {
            completionHandler(_storageItem.value);
        }
    } else {
        __block MKKeyValueDBItem *storageItem = nil;
        @weakify(self);
        [self inTransaction:^(FMDatabase *db, BOOL *rollback) {
            @strongify(self);
            NSString* query = [NSString stringWithFormat:@"select * from %@ where key = '%@'", (tableName ? tableName : self.tableName), key];
            [db selectWithQuery:query resultBlock:^(FMResultSet * _Nonnull result) {
                storageItem = [MKKeyValueDBItem itemWithResult:result];
            }];
        } isAsync:YES completion:^{
            if (storageItem) {
                LOCK([self.storageItems setObject:storageItem forKey:key]);
            }
            
            if (completionHandler) {
                completionHandler(storageItem.value);
            }
        }];
    }
}

- (void)saveDataWithValue:(id)value forKey:(NSString *)key {
    [self saveDataWithValue:value forKey:key tableName:nil];
}

- (void)saveDataWithValue:(id)value forKey:(NSString *)key tableName:(NSString *)tableName {
    MKKeyValueDBItem *storageItem = [MKKeyValueDBItem itemWithValue:value forKey:key];
    LOCK([_storageItems setObject:storageItem forKey:key]);
    
    [self inTransaction:^(FMDatabase *db, BOOL *rollback) {
        NSString *query = [NSString stringWithFormat:@"select * from %@ where key = '%@'", (tableName ? tableName : self.tableName), key];
        if ([db selectWithQuery:query resultBlock:^(FMResultSet * _Nonnull result) {}]) {
            // 更新
            [db updateWithTableName:(tableName ? tableName : self.tableName) dataBaseModel:storageItem where:@{@"key": key}];
        } else {
            // 新增
            [db insertWithTableName:(tableName ? tableName : self.tableName) dataBaseModel:storageItem];
        }
    } isAsync:YES completion:nil];
}

- (void)removeForKey:(NSString *)key {
    [self removeForKey:key tableName:nil];
}

- (void)removeForKey:(NSString *)key tableName:(NSString *)tableName {
    LOCK([_storageItems removeObjectForKey:key]);
    
    [self inTransaction:^(FMDatabase *db, BOOL *rollback) {
        NSString *query = [NSString stringWithFormat:@"delete from %@ where key = %@", (tableName ? tableName : self.tableName), key];
        [db deleteWithQuery:query];
    } isAsync:YES completion:nil];
}

@end

@implementation MKKeyValueDBItem

+ (instancetype)itemWithValue:(NSString *)value forKey:(NSString *)key {
    MKKeyValueDBItem* model = [[MKKeyValueDBItem alloc] init];
    model.value = value;
    model.key = key;
    return model;
}

+ (instancetype)itemWithResult:(FMResultSet *)result {
    MKKeyValueDBItem* item = [[MKKeyValueDBItem alloc] init];
    item.value = [result stringForColumn:@"value"];
    item.key = [result stringForColumn:@"key"];
    return item;
}

@end
