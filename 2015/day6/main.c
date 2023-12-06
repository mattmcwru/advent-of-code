#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>  


void print_match(regmatch_t rm, char* str) {
    int length = rm.rm_eo - rm.rm_so;

    if (rm.rm_so > -1 && length > 0)
        printf("%.*s", length, str + rm.rm_so);
}


int main() {

    char map[1000][1000] = {0};

    FILE *fp = fopen("data.txt", "r");
    if (fp == NULL) {
        printf("Error opening file\n");
        return -1;
    }

    const char *regex_str = "^(toggle|turn off|turn on)?[[:space:]]([0-9]+),([0-9]+) through ([0-9]+),([0-9]+)";
    const int regex_groups = 6;

    regex_t regex;
    regmatch_t regex_matches[regex_groups];
    int resp;
    char msgbuf[100];

    long x0, y0;
    long x1, y1;
    int operator;
    char tolbuf[24];

    resp = regcomp(&regex, regex_str, REG_EXTENDED);
    if (resp) {
        fprintf(stderr, "regcomp failed [%d]\n", resp);
        return -1;
    }

//    char *test_str = "turn on 599,989 through 806,993";

    char buf[50];

    while ((NULL != fgets(buf, sizeof(buf), fp))) {


        resp = regexec(&regex, buf, regex_groups, regex_matches, 0);
        if (!resp) {
            //printf("Match");
            //for (int g=0; g<regex_groups; g++)
            //    printf(" (%lld %lld)", regex_matches[g].rm_so, regex_matches[g].rm_eo);
            //printf("\n");


            //print_match(regex_matches[1], buf);
            //printf(" (");
            //print_match(regex_matches[2], buf);
            //printf(",");
            //print_match(regex_matches[3], buf);
            //printf(") (");
            //print_match(regex_matches[4], buf);
            //printf(",");
            //print_match(regex_matches[5], buf);
            //printf(")\n");

            if (0 == strncmp(buf + regex_matches[1].rm_so, "turn on", strlen("turn on"))) {
                operator = 1;
            } else if (0 == strncmp(buf + regex_matches[1].rm_so, "turn off", strlen("turn off"))) {
                operator = 2;
            } else if (0 == strncmp(buf + regex_matches[1].rm_so, "toggle", strlen("toggle"))) {
                operator = 3;
            } else {
                operator = 0;
                printf("Invalid operator\n");
            }

            memset(tolbuf, 0, sizeof(tolbuf));
            strncpy(tolbuf, buf + regex_matches[2].rm_so, regex_matches[2].rm_eo - regex_matches[2].rm_so);
            x0 = strtol(tolbuf, NULL, 10);

            memset(tolbuf, 0, sizeof(tolbuf));
            strncpy(tolbuf, buf + regex_matches[3].rm_so, regex_matches[3].rm_eo - regex_matches[3].rm_so);
            y0 = strtol(tolbuf, NULL, 10);

            memset(tolbuf, 0, sizeof(tolbuf));
            strncpy(tolbuf, buf + regex_matches[4].rm_so, regex_matches[4].rm_eo - regex_matches[4].rm_so);
            x1 = strtol(tolbuf, NULL, 10);

            memset(tolbuf, 0, sizeof(tolbuf));
            strncpy(tolbuf, buf + regex_matches[5].rm_so, regex_matches[5].rm_eo - regex_matches[5].rm_so);
            y1 = strtol(tolbuf, NULL, 10);

            
            //printf("%d (%ld, %ld) (%ld, %ld)\n", operator, x0, y0, x1, y1);


            for (long x = x0; x <= x1; x++) {
                for (long y = y0; y <= y1; y++) {

                    #if 0 // part 1
                    switch (operator) {
                        case 1: map[x][y] = 1; break;
                        case 2: map[x][y] = 0; break;
                        case 3: map[x][y] ^= 1; break;
                    }
                    #else // part 2
                        switch (operator) {
                            case 1: map[x][y]++; break;
                            case 2: map[x][y]--; if (map[x][y] < 0) map[x][y] = 0; break;
                            case 3: map[x][y] += 2; break;
                        }
                    #endif
                }
            }

        }
        else if (resp == REG_NOMATCH) {
            printf("No match\n");
        }
        else {
            regerror(resp, &regex, msgbuf, sizeof(msgbuf));
            fprintf(stderr, "Regex match failed: %s\n", msgbuf);
        }
    }

    int lights_on = 0;
    for (int x = 0; x < 1000; x++) {
        for (int y = 0; y < 1000; y++) {
            lights_on += map[x][y];
        }
    }

    printf("Lights on = %d\n", lights_on);

    regfree(&regex);

    fclose(fp);
    return 0;
}