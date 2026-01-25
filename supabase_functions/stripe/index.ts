    // Supabase Edge Function для работы со Stripe
    // Разверните эту функцию в Supabase Dashboard → Edge Functions

    import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
    import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'
    import Stripe from 'npm:stripe@14.14.0'

    // Crypto provider для Deno
    const cryptoProvider = Stripe.createSubtleCryptoProvider()

    const stripeKey = Deno.env.get('STRIPE_SECRET_KEY')
    if (!stripeKey) {
    console.error('STRIPE_SECRET_KEY is not set!')
    }

    const stripe = new Stripe(stripeKey || '', {
    apiVersion: '2023-10-16',
    })

    // Supabase client с service role для записи в БД
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
    }

    serve(async (req: Request) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const url = new URL(req.url)
        const path = url.pathname.split('/').pop()

        switch (path) {
        case 'create-payment-intent':
            return await createPaymentIntent(req)
        case 'create-subscription':
            return await createSubscription(req)
        case 'cancel-subscription':
            return await cancelSubscription(req)
        case 'create-setup-intent':
            return await createSetupIntent(req)
        case 'payment-methods':
            return await getPaymentMethods(req)
        case 'webhook':
            return await handleWebhook(req)
        default:
            return new Response(
            JSON.stringify({ error: 'Unknown endpoint' }),
            { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }
    } catch (error) {
        return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
    })

    // Создание PaymentIntent для одноразового платежа
    async function createPaymentIntent(req: Request) {
    const { amount, currency, customer_id, metadata } = await req.json()

    // Получаем или создаем Stripe Customer
    let stripeCustomerId = await getOrCreateStripeCustomer(customer_id)

    const paymentIntent = await stripe.paymentIntents.create({
        amount,
        currency: currency || 'rub',
        customer: stripeCustomerId,
        metadata: {
        ...metadata,
        supabase_user_id: customer_id,
        },
        automatic_payment_methods: {
        enabled: true,
        },
    })

    return new Response(
        JSON.stringify({
        client_secret: paymentIntent.client_secret,
        payment_intent_id: paymentIntent.id,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
    }

    // Создание подписки
    async function createSubscription(req: Request) {
    const { price_id, customer_id } = await req.json()

    let stripeCustomerId = await getOrCreateStripeCustomer(customer_id)

    const subscription = await stripe.subscriptions.create({
        customer: stripeCustomerId,
        items: [{ price: price_id }],
        payment_behavior: 'default_incomplete',
        payment_settings: { save_default_payment_method: 'on_subscription' },
        expand: ['latest_invoice.payment_intent'],
    })

    const invoice = subscription.latest_invoice as Stripe.Invoice
    const paymentIntent = invoice.payment_intent as Stripe.PaymentIntent

    return new Response(
        JSON.stringify({
        subscription_id: subscription.id,
        client_secret: paymentIntent.client_secret,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
    }

    // Отмена подписки
    async function cancelSubscription(req: Request) {
    const { subscription_id } = await req.json()

    await stripe.subscriptions.cancel(subscription_id)

    return new Response(
        JSON.stringify({ success: true }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
    }

    // Создание SetupIntent для сохранения карты
    async function createSetupIntent(req: Request) {
    const { customer_id } = await req.json()

    let stripeCustomerId = await getOrCreateStripeCustomer(customer_id)

    const setupIntent = await stripe.setupIntents.create({
        customer: stripeCustomerId,
        automatic_payment_methods: { enabled: true },
    })

    return new Response(
        JSON.stringify({ client_secret: setupIntent.client_secret }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
    }

    // Получение способов оплаты
    async function getPaymentMethods(req: Request) {
    const url = new URL(req.url)
    const customerId = url.searchParams.get('customer_id')

    if (!customerId) {
        return new Response(
        JSON.stringify({ error: 'customer_id required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }

    const stripeCustomerId = await getStripeCustomerId(customerId)
    if (!stripeCustomerId) {
        return new Response(
        JSON.stringify({ payment_methods: [] }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }

    const paymentMethods = await stripe.paymentMethods.list({
        customer: stripeCustomerId,
        type: 'card',
    })

    return new Response(
        JSON.stringify({
        payment_methods: paymentMethods.data.map(pm => ({
            id: pm.id,
            type: pm.type,
            card: pm.card ? {
            brand: pm.card.brand,
            last4: pm.card.last4,
            exp_month: pm.card.exp_month,
            exp_year: pm.card.exp_year,
            } : null,
        })),
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
    }

    // Обработка вебхуков от Stripe
    async function handleWebhook(req: Request) {
    const signature = req.headers.get('stripe-signature')
    const body = await req.text()
    const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')

    if (!signature) {
        return new Response('Missing stripe-signature header', { status: 400 })
    }
    
    if (!webhookSecret) {
        return new Response('STRIPE_WEBHOOK_SECRET not configured', { status: 500 })
    }

    let event: Stripe.Event

    try {
        // Используем асинхронную версию с crypto provider для Deno
        event = await stripe.webhooks.constructEventAsync(
        body, 
        signature, 
        webhookSecret,
        undefined,
        cryptoProvider
        )
    } catch (err) {
        console.error('Webhook signature verification failed:', err.message)
        return new Response(`Webhook Error: ${err.message}`, { status: 400 })
    }

    // Обработка различных событий
    switch (event.type) {
        case 'payment_intent.succeeded':
        await handlePaymentSucceeded(event.data.object as Stripe.PaymentIntent)
        break
        case 'payment_intent.payment_failed':
        await handlePaymentFailed(event.data.object as Stripe.PaymentIntent)
        break
        case 'customer.subscription.created':
        case 'customer.subscription.updated':
        await handleSubscriptionUpdated(event.data.object as Stripe.Subscription)
        break
        case 'customer.subscription.deleted':
        await handleSubscriptionDeleted(event.data.object as Stripe.Subscription)
        break
        case 'invoice.paid':
        console.log('Invoice paid:', event.data.object)
        break
        case 'invoice.payment_failed':
        console.log('Invoice payment failed:', event.data.object)
        break
    }

    return new Response(JSON.stringify({ received: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
    }

    // Обработчики событий

    async function handlePaymentSucceeded(paymentIntent: Stripe.PaymentIntent) {
    console.log('Payment succeeded:', paymentIntent.id)
    
    const userId = paymentIntent.metadata?.supabase_user_id
    if (!userId) return

    await supabase.from('payments').insert({
        user_id: userId,
        amount: paymentIntent.amount,
        currency: paymentIntent.currency.toUpperCase(),
        status: 'completed',
        stripe_payment_id: paymentIntent.id,
        description: paymentIntent.description || 'Оплата',
        metadata: paymentIntent.metadata,
    })
    }

    async function handlePaymentFailed(paymentIntent: Stripe.PaymentIntent) {
    console.log('Payment failed:', paymentIntent.id)
    
    const userId = paymentIntent.metadata?.supabase_user_id
    if (!userId) return

    await supabase.from('payments').insert({
        user_id: userId,
        amount: paymentIntent.amount,
        currency: paymentIntent.currency.toUpperCase(),
        status: 'failed',
        stripe_payment_id: paymentIntent.id,
        description: paymentIntent.description || 'Оплата',
        metadata: paymentIntent.metadata,
    })
    }

    async function handleSubscriptionUpdated(subscription: Stripe.Subscription) {
    console.log('Subscription updated:', subscription.id)
    
    try {
        // Получаем user_id из customer metadata
        const customer = await stripe.customers.retrieve(subscription.customer as string) as Stripe.Customer
        let userId = customer.metadata?.supabase_user_id
        
        // Если нет user_id - пробуем найти пользователя по email
        if (!userId && customer.email) {
        console.log('Looking up user by email:', customer.email)
        
        // Ищем пользователя в Supabase по email
        const { data: profile } = await supabase
            .from('profiles')
            .select('id')
            .eq('email', customer.email)
            .single()
        
        if (profile) {
            userId = profile.id
            console.log('Found user by email:', userId)
            
            // Обновляем metadata клиента в Stripe для будущих запросов
            await stripe.customers.update(customer.id, {
            metadata: { supabase_user_id: userId }
            })
        } else {
            // Пробуем найти в auth.users
            const { data: authUser } = await supabase
            .from('auth.users')
            .select('id')
            .eq('email', customer.email)
            .single()
            
            if (authUser) {
            userId = authUser.id
            console.log('Found auth user by email:', userId)
            
            await stripe.customers.update(customer.id, {
                metadata: { supabase_user_id: userId }
            })
            }
        }
        }
        
        if (!userId) {
        console.log('No user found for email:', customer.email)
        return
        }

        // Определяем plan_id из price metadata (приоритет) или продукта
        const price = subscription.items.data[0]?.price
        const priceId = price?.id || ''
        const productId = price?.product as string || ''
        
        let planId = 'basic' // По умолчанию
        
        // 1. ПРИОРИТЕТ: проверяем metadata цены (для структуры 1 продукт = несколько цен)
        if (price?.metadata?.plan_id) {
            planId = price.metadata.plan_id
            console.log('Plan from price metadata:', planId)
        } 
        // 2. Проверяем nickname цены (можно указать в Stripe Dashboard)
        else if (price?.nickname) {
            const nickname = price.nickname.toLowerCase()
            if (nickname.includes('premium') || nickname.includes('премиум')) {
                planId = 'premium'
            } else if (nickname.includes('basic') || nickname.includes('базов')) {
                planId = 'basic'
            }
            console.log('Plan from price nickname:', planId, '- nickname:', price.nickname)
        }
        // 3. Определяем по сумме (fallback)
        else if (price?.unit_amount) {
            // $2.00 = 200 cents = premium, $1.00 = 100 cents = basic
            if (price.unit_amount >= 200) {
                planId = 'premium'
            } else {
                planId = 'basic'
            }
            console.log('Plan from price amount:', planId, '- amount:', price.unit_amount)
        }
        // 4. Fallback: проверяем metadata продукта
        else {
            try {
                const product = await stripe.products.retrieve(productId)
                if (product.metadata?.plan_id) {
                    planId = product.metadata.plan_id
                }
                console.log('Plan from product metadata:', planId)
            } catch (e) {
                console.log('Could not retrieve product, using default plan:', planId)
            }
        }

        // Безопасное преобразование дат
        const periodStart = subscription.current_period_start 
        ? new Date(subscription.current_period_start * 1000).toISOString() 
        : new Date().toISOString()
        
        const periodEnd = subscription.current_period_end 
        ? new Date(subscription.current_period_end * 1000).toISOString() 
        : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString() // +30 дней

        // Проверяем, существует ли уже подписка
        const { data: existing } = await supabase
        .from('subscriptions')
        .select('id')
        .eq('stripe_subscription_id', subscription.id)
        .single()

        let error
        if (existing) {
        // Обновляем существующую подписку
        const result = await supabase.from('subscriptions').update({
            plan_id: planId,
            status: subscription.status,
            current_period_start: periodStart,
            current_period_end: periodEnd,
            cancel_at_period_end: subscription.cancel_at_period_end || false,
        }).eq('stripe_subscription_id', subscription.id)
        error = result.error
        } else {
        // Создаем новую подписку
        const result = await supabase.from('subscriptions').insert({
            user_id: userId,
            plan_id: planId,
            stripe_subscription_id: subscription.id,
            stripe_customer_id: subscription.customer as string,
            status: subscription.status,
            current_period_start: periodStart,
            current_period_end: periodEnd,
            cancel_at_period_end: subscription.cancel_at_period_end || false,
        })
        error = result.error
        }
        
        if (error) {
        console.error('Error upserting subscription:', error)
        }
    } catch (err) {
        console.error('handleSubscriptionUpdated error:', err)
    }
    }

    async function handleSubscriptionDeleted(subscription: Stripe.Subscription) {
    console.log('Subscription deleted:', subscription.id)
    
    try {
        const { error } = await supabase
        .from('subscriptions')
        .update({ status: 'canceled' })
        .eq('stripe_subscription_id', subscription.id)
        
        if (error) {
        console.error('Error deleting subscription:', error)
        }
    } catch (err) {
        console.error('handleSubscriptionDeleted error:', err)
    }
    }

    // Вспомогательные функции

    async function getOrCreateStripeCustomer(supabaseUserId: string): Promise<string> {
    // Проверяем, есть ли уже Stripe Customer
    const existing = await getStripeCustomerId(supabaseUserId)
    if (existing) return existing

    // Создаем нового клиента
    const customer = await stripe.customers.create({
        metadata: { supabase_user_id: supabaseUserId },
    })

    return customer.id
    }

    async function getStripeCustomerId(supabaseUserId: string): Promise<string | null> {
    // Ищем существующего клиента по metadata
    const customers = await stripe.customers.search({
        query: `metadata['supabase_user_id']:'${supabaseUserId}'`,
    })
    
    if (customers.data.length > 0) {
        return customers.data[0].id
    }
    
    return null
    }
