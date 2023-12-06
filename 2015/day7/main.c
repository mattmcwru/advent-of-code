#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <regex.h>
#include <string.h>



typedef struct _gate_t {
    uint16_t id;
    int value;
    enum {NONE, AND, OR, NOT, RSHIFT, LSHIFT, CONST} operator;
    struct _gate_t *input1;
    struct _gate_t *input2;
} gate_t;

gate_t gate_list[500] = {0};  // Fixed tree size (make as large as needed)

gate_t *find_node(uint16_t id) {
    for (int i = 0; i < sizeof(gate_list)/sizeof(gate_t); i++) {
        if (gate_list[i].id == id)
            return &gate_list[i];
    }
    return NULL;
}

gate_t *add_node(char* id, char *op, char *input1, char *input2) {
    union {
        uint16_t id;
        char c[2];
    } uid;

    // Return nothing if no id
    if (NULL == id) {
        return NULL;
    }

    // Convert id to uint
    int len = strlen(id);
    if (len > 0 && len < 3) {
        uid.c[0] = id[0];
        uid.c[1] = id[1];
    }

    // Check for existing node
    gate_t *node = find_node(uid.id);
    if (node != NULL) {
        // Assign data to existing node
    } else {
        // Create new node
        node = malloc(sizeof(gate_t));
        if (node == NULL) {
            fprintf(stderr, "Memory allocation error for %s\n", id);
            return NULL;
        }
    }

    // Assign operator
    if (NULL == op) {
        node->operator = NONE;
    } else if (0 == strcmp(op, "AND")) {
        node->operator = AND;
    } else if (0 == strcmp(op, "OR")) {

    }

    // Assign input1


    // Assign input 2


    // Remember to free this later
    return node;
}

// Duplicate string from regex match.  String MUST BE freed after usage.
char *get_str(regmatch_t *pm, char *buf) {
    if (pm->rm_so != -1) {
        return strndup(buf + pm->rm_so,pm->rm_eo - pm->rm_so);
    }
    return NULL;
}


int main() {

    FILE *fp = fopen("data.txt", "r");    
    if (fp == NULL) {
        printf("Error opening file\n");
        return -1;
    }

    const char *regex_str = "([a-z0-9]+)?[[:space:]]?(AND|OR|NOT|RSHIFT|LSHIFT)?[[:space:]]?([a-z0-9]+)? -> ([a-z]{1,2})+$";
    const int regex_groups = 5;

    regex_t regex;
    regmatch_t regex_matches[regex_groups];
    int resp;


   resp = regcomp(&regex, regex_str, REG_EXTENDED | REG_NEWLINE);
    if (resp) {
        fprintf(stderr, "regcomp failed [%d]\n", resp);
        fclose(fp);
        return -1;
    }


    char buf[50];


    while ((NULL != fgets(buf, sizeof(buf), fp))) {

        resp = regexec(&regex, buf, regex_groups, regex_matches, 0);
        if (!resp) {
        #if 1
            printf("Match");
            for (int g=0; g<regex_groups; g++)
                printf(" (%lld %lld)", regex_matches[g].rm_so, regex_matches[g].rm_eo);
            printf("  %s", buf);
        #endif
        } else if (resp == REG_NOMATCH) {
            printf("No match  %s", buf);
            continue;
        } else {
            char msgbuf[100];
            regerror(resp, &regex, msgbuf, sizeof(msgbuf));
            fprintf(stderr, "Regex match failed: %s\n", msgbuf);
            break;
        }


        char* id = get_str(&regex_matches[4], buf);
        char* op = get_str(&regex_matches[2], buf);
        char* input1 = get_str(&regex_matches[1], buf);
        char* input2 = get_str(&regex_matches[3], buf);

        printf("%s %s %s %s\n", id, op, input1, input2);

        add_node(id, op, input1, input2);

        free(id);
        free(op);
        free(input1);
        free(input2);

        //break;
    }


    // recurse through tree starting at node a


    regfree(&regex);

    fclose(fp);
    return 0;
}