import { createRouter, createWebHashHistory } from 'vue-router';
import CommonStorageBase from "@/components/storage/CommonStorageBase";

const router = createRouter({
    history: createWebHashHistory(),
    routes: [
        {
            path: '/',
            component: () => import('../components/pages/Index.vue'),
        },
        {
            path: '/organization',
            component: () => import('../components/OrganizationChartChat.vue'),
            meta: {
                requiresAuth: true
            },
        },
        {
            path: '/definitions',
            component: () => import('../components/ProcessManagerChat.vue'),
            meta: {
                requiresAuth: true
            },
        },
        {
            path: '/definitions/:id',
            component: () => import('../components/ProcessManagerChat.vue'),
            meta: {
                requiresAuth: true
            },
        },
        {
            path: '/instances',
            component: () => import('../components/ProcessParticipantChat.vue'),
            meta: {
                requiresAuth: true
            },
        },
        {
            path: '/instances/:id',
            component: () => import('../components/ProcessParticipantChat.vue'),
            meta: {
                requiresAuth: true
            },
        },
        {
            path: '/todolist',
            component: () => import('../components/ui/TodolistGrid.vue'),
            meta: {
                requiresAuth: true
            },
        },
    ],
});

router.beforeEach(async (to, from, next) => {
    const storage = new CommonStorageBase(this);
    await storage.getUserInfo();
    
    let isLogin = false;
    if (storage.isLogin) {
        isLogin = true;
    } else {
        isLogin = false;
    }
    
    if (to.matched.some(record => record.meta.requiresAuth)) {
        if (!isLogin) {
            next('/');
        } else {
            next();
        }
    } else {
        next();
    }
});

export default router;
