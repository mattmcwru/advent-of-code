#import <stdio.h>

// This approach is dumb since the fixed array size is incremented until it works for the input.
// And it is slow since it does a linear search for each position.

#define POS_MAX 4096

typedef struct {
    int x;
    int y;
} pos_t;

typedef struct {
    int index;
    pos_t list[POS_MAX];
} poslist_t;

poslist_t travel_list = {0, {0}};


int is_new_house(poslist_t *plist, pos_t p) {
    // search the list
    for (int i = 0; i <= plist->index; i++) {
        if (plist->list[i].x == p.x && plist->list[i].y == p.y)
            return 0;
    }
    return 1;
}

int add_house(poslist_t *plist, pos_t p) {
    if (plist->index < POS_MAX-1) {
        plist->index++;
        plist->list[plist->index].x = p.x;
        plist->list[plist->index].y = p.y;
        return 0;
    }

    printf("Ran out of memory\n");
    return -1;
}

// Return 1 if new house, else 0
int check_house(poslist_t *plist, pos_t p) {
    if (is_new_house(plist, p)) {
        add_house(plist, p);
        return 1;
    }
    return 0;
}

int main() {

    FILE *fp = fopen("data.txt", "r");
    if (fp == NULL) {
        printf("Error opening file\n");
        return -1;
    }

    char c;
    int house_count = 1;
    int turn = 0;

    pos_t current_pos[2] = { {0, 0}, {0, 0} };

    do {
        c = fgetc(fp);

        switch(c) {
            case '>': current_pos[turn].x++; house_count += check_house(&travel_list, current_pos[turn]); break;
            case '<': current_pos[turn].x--; house_count += check_house(&travel_list, current_pos[turn]); break;
            case '^': current_pos[turn].y++; house_count += check_house(&travel_list, current_pos[turn]); break;
            case 'v': current_pos[turn].y--; house_count += check_house(&travel_list, current_pos[turn]); break;

            case '\n': 
            case EOF : break;

            default:
                printf("Bad input %c", c);
        }

        //printf("%d %d\n", turn, lists[turn]->index);

        turn ^= 1;  // Toggle between 0 and 1

    } while (c != EOF);

    printf("House count: %d\n", house_count);

    fclose(fp);
    return 0;
}