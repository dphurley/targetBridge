#include "input_queue.h"

#include <stdio.h>
#include <string.h>

static int checks = 0;
static int failures = 0;

#define CHECK(condition, message) do { \
    checks++; \
    if (!(condition)) { \
        fprintf(stderr, "FAIL: %s\n", message); \
        failures++; \
    } \
} while (0)

static struct tb_input_event event(enum tb_input_event_kind kind, int value) {
    struct tb_input_event result;
    memset(&result, 0, sizeof(result));
    result.kind = kind;
    result.dx = value;
    result.key_code = (uint16_t)value;
    return result;
}

int main(void) {
    struct tb_input_queue queue = {0};
    struct tb_input_event out;
    int saw_down = 0;
    int saw_up = 0;

    struct tb_input_event first = event(TB_INPUT_EVENT_KEY_DOWN, 12);
    struct tb_input_event second = event(TB_INPUT_EVENT_KEY_UP, 12);
    CHECK(tb_input_queue_push(&queue, &first) == 1, "first event queued");
    CHECK(tb_input_queue_push(&queue, &second) == 1, "second event queued");
    CHECK(tb_input_queue_pop(&queue, &out) == 1 && out.kind == TB_INPUT_EVENT_KEY_DOWN,
          "queue preserves FIFO order");
    CHECK(tb_input_queue_pop(&queue, &out) == 1 && out.kind == TB_INPUT_EVENT_KEY_UP,
          "queue preserves key release");

    /* Exercise the same overflow policy after the circular head has wrapped. */
    memset(&queue, 0, sizeof(queue));
    for (int i = 0; i < 16; i++) {
        struct tb_input_event warmup = event(TB_INPUT_EVENT_MOVE, i);
        CHECK(tb_input_queue_push(&queue, &warmup) == 1, "wrap warmup queued");
    }
    for (int i = 0; i < 16; i++) {
        CHECK(tb_input_queue_pop(&queue, &out) == 1, "wrap warmup popped");
    }
    for (int i = 0; i < TB_INPUT_QUEUE_CAPACITY - 1; i++) {
        struct tb_input_event wrapped_move = event(TB_INPUT_EVENT_MOVE, 1000 + i);
        CHECK(tb_input_queue_push(&queue, &wrapped_move) == 1, "wrapped motion queued");
    }
    CHECK(tb_input_queue_push(&queue, &first) == 1, "wrapped key down fills queue");
    CHECK(tb_input_queue_push(&queue, &second) == 1,
          "wrapped overflow preserves key release");
    while (tb_input_queue_pop(&queue, &out)) {
        if (out.kind == TB_INPUT_EVENT_KEY_DOWN) saw_down++;
        if (out.kind == TB_INPUT_EVENT_KEY_UP) saw_up++;
    }
    CHECK(saw_down == 1 && saw_up == 1,
          "wrapped eviction preserves lifecycle order");

    memset(&queue, 0, sizeof(queue));
    for (int i = 0; i < TB_INPUT_QUEUE_CAPACITY - 1; i++) {
        struct tb_input_event move = event(TB_INPUT_EVENT_MOVE, i);
        CHECK(tb_input_queue_push(&queue, &move) == 1, "motion burst queued");
    }
    CHECK(tb_input_queue_push(&queue, &first) == 1, "key down fills queue");
    CHECK(tb_input_queue_push(&queue, &second) == 1,
          "key up evicts motion instead of being discarded");
    saw_down = 0;
    saw_up = 0;
    while (tb_input_queue_pop(&queue, &out)) {
        if (out.kind == TB_INPUT_EVENT_KEY_DOWN) saw_down++;
        if (out.kind == TB_INPUT_EVENT_KEY_UP) saw_up++;
    }
    CHECK(saw_down == 1, "key down survives motion overflow");
    CHECK(saw_up == 1, "key up survives motion overflow");

    memset(&queue, 0, sizeof(queue));
    for (int i = 0; i < TB_INPUT_QUEUE_CAPACITY - 1; i++) {
        struct tb_input_event move = event(TB_INPUT_EVENT_MOVE, i);
        CHECK(tb_input_queue_push(&queue, &move) == 1, "mouse motion burst queued");
    }
    struct tb_input_event left_down = event(TB_INPUT_EVENT_LEFT_DOWN, 0);
    struct tb_input_event left_up = event(TB_INPUT_EVENT_LEFT_UP, 0);
    CHECK(tb_input_queue_push(&queue, &left_down) == 1, "mouse down fills queue");
    CHECK(tb_input_queue_push(&queue, &left_up) == 1,
          "mouse up evicts motion instead of being discarded");
    saw_down = 0;
    saw_up = 0;
    while (tb_input_queue_pop(&queue, &out)) {
        if (out.kind == TB_INPUT_EVENT_LEFT_DOWN) saw_down++;
        if (out.kind == TB_INPUT_EVENT_LEFT_UP) saw_up++;
    }
    CHECK(saw_down == 1, "mouse down survives motion overflow");
    CHECK(saw_up == 1, "mouse up survives motion overflow");

    memset(&queue, 0, sizeof(queue));
    for (int i = 0; i < TB_INPUT_QUEUE_CAPACITY; i++) {
        struct tb_input_event critical = event(TB_INPUT_EVENT_KEY_DOWN, i);
        CHECK(tb_input_queue_push(&queue, &critical) == 1, "critical event queued");
    }
    struct tb_input_event move = event(TB_INPUT_EVENT_MOVE, 5);
    CHECK(tb_input_queue_push(&queue, &move) == 0,
          "lossy motion is discarded before a lifecycle event");
    CHECK(queue.count == TB_INPUT_QUEUE_CAPACITY,
          "discarded motion leaves critical queue intact");

    CHECK(tb_input_queue_push(&queue, &second) == -1,
          "critical-only overflow requests safe deactivation");
    CHECK(queue.count == 1, "unsafe backlog is collapsed");
    CHECK(tb_input_queue_pop(&queue, &out) == 1 &&
          out.kind == TB_INPUT_EVENT_DEACTIVATE_CONTROL,
          "overflow emits the existing release-all command");
    CHECK(tb_input_queue_pop(&queue, &out) == 0, "queue is empty after fail-safe");

    printf("input queue tests: %d checks, %d failures\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
